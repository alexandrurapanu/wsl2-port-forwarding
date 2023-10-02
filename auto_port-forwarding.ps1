<#
.SYNOPSIS
	A little basic tool that configures a bridged connection between a WSL instance and the Host.
.DESCRIPTION
	When a service is running in a WSL instance, like Ubuntu for example, we want the service
	to be accessible from any device that is connected to the local network.

	This script automates the configuration process of a bridged connection between a WSL 
	instance and the Host. Thus, forwarding the TCP ports of WSL 2 services to the Host.
.PARAMETER -WslInstanceName
	Run: "wsl -l -v" to get all the WSL instances
	And then copy the name of the instance
	If the wsl instance on which your service is not set as the default one, then run: 
	"wsl --setdefault DISTRO-NAME" where DISTRO-NAME is the name of the wsl instance distro.
	Example: wsl --setdefault Ubuntu-22.04
.PARAMETER -ListenPort
	Represents the Port number which your service will be accessible from within your LAN
.PARAMETER -ConnectPort
	The port number of the service that is running on the WSL instance
.PARAMETER -RuleName
	This will be the given name of the inbound rule created in Firewall
	For example you can name it "WSL8080"
.EXAMPLE
	[Note]: Make sure to run the command As Administrator

	powershell.exe -ExecutionPolicy Bypass -File "auto_port-forwarding.ps1" -WslInstanceName "Ubuntu-22.04" -ListenPort 8080 -ConnectPort 8080 -RuleName "WSL8080"
.NOTES
	Author: AR. (https://github.com/alexandrurapanu)
	Date: May 18, 2023
#>
param (
	[Parameter(Mandatory=$true)]
	[string]$WslInstanceName,
	
	[Parameter(Mandatory=$true)]
	[int]$ListenPort,

	[Parameter(Mandatory=$true)]
	[int]$ConnectPort,

	[Parameter(Mandatory=$false)]
	[string]$RuleName
)

# Returns the IP of the Host
function GetHostIP {
	try {
		# Retrieve the LAN IP of the local machine
		$getHostIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias Ethernet).IPAddress.Trim()

		if (-not $?) {
			throw $getHostIP
		} else {
			return $getHostIP
		}
	}
	catch {
		Write-Host "`n[ERROR] An error occurred: $_" -ForegroundColor Red
	}
}

# Retrieve the IP of the active WSL instance
function GetWslInstanceIP {
	try {
		
		$wslIP = (wsl hostname -I).Trim()

		if (-not $?) {
			throw $wslIP
		} else {
			return $wslIP
		}
	}
	catch {
		Write-Host "`n[ERROR] An error occurred: $_" -ForegroundColor Red
	}
}

# Adds a PortProxy rule
function AddPortProxyRule {

	try {
		# Set the default WSL instance
		$setDefaultInstance = wsl --set-default $WslInstanceName

		if (-not $?) {
			throw $setDefaultInstance
		}
	}
	catch {
		Write-Host "`n[ERROR] An error occurred: $_" -ForegroundColor Red
	}

	$getHostIP = GetHostIP
	$getWslIP = GetWslInstanceIP

	try {
		# Add a PortProxy Rule
		$add_portproxy_rule = netsh interface portproxy add v4tov4 listenport=$ListenPort listenaddress=$getHostIP connectport=$ConnectPort connectaddress=$getWslIP

		if (-not $?) {
			throw $add_portproxy_rule
		} else {
			Write-Host "`n[INFO] PortProxy Rule has been successfully created !" -ForegroundColor Green
			Write-Host "`n`tHost IP: `t $getHostIP" -ForegroundColor Blue
			Write-Host "`tPort: `t`t $ListenPort" -ForegroundColor Blue
			Write-Host "`tWSL Instance IP: $getWslIP" -ForegroundColor Cyan
			Write-Host "`tPort: `t`t $ConnectPort" -ForegroundColor Cyan
		}
	}
	catch {
		Write-Host "[ERROR] An error occurred: $_" -ForegroundColor Red
	}

}

# Removes a PortProxy rule
function DeletePortProxyRule {

	$getHostIp = GetHostIP

	try {
		# Remove a PortProxy Rule
		$delete_portproxy_rule = netsh interface portproxy delete v4tov4 listenport=$ListenPort listenaddress=$getHostIp

		if (-not $?) {
			throw $delete_portproxy_rule
		} else {
			Write-Host "`n[INFO] PortProxy Rule has been successfully removed !" -ForegroundColor Green
		}
	}
	catch {
		Write-Host "`n[ERROR] An error occurred: $_" -ForegroundColor Red
	}
}

# Enable/Disable an Inbound Rule in the Firewall
function InboundRuleSwitch {
	param (
		[Parameter(Mandatory=$true)]
		[string]$SetTrueFalse
	)

	# Check if the rule already exists
	$rule = Get-NetFirewallRule | Where-Object {
		$_.Action -eq 'Allow' -and
		$_.Direction -eq 'Inbound' -and
		$_.DisplayName -eq $RuleName -and
		(Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_).LocalPort -eq $ListenPort
	}

	if ($rule) {
		# Enable the rule
		Set-NetFirewallRule -DisplayName $RuleName -Enabled $SetTrueFalse
		Write-Host "[INFO] Inbound rule '$RuleName' for port '$ListenPort' has been " -NoNewline -ForegroundColor Green
		if ($SetTrueFalse -eq "True") {
			Write-Host "enabled !" -ForegroundColor Green
		} elseif ($SetTrueFalse -eq "False") {
			Write-Host "disabled !`n" -ForegroundColor Green
		} else {
			Write-Host "`n[WARN] 'Set-NetFirewallRule' only accepts values like 'True' or 'False' !" -ForegroundColor Yellow
		}
	} else {
		Write-Host "`n[INFO] Inbound rule '$RuleName' for port '$ListenPort' not found !" -ForegroundColor Green
	}
}

# Adding an Inbound Rule to the Firewall
function AddInboundRule {

	# Check if the rule already exists
	$existingRule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue

	if ($existingRule) {
		Write-Host "`n[INFO] Firewall rule '$RuleName' already exists." -ForegroundColor Green
		InboundRuleSwitch -SetTrueFalse "True"
	} else {
		# Create a new inbound rule for the specified port
		New-NetFirewallRule -DisplayName $RuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $ListenPort
		Write-Host "`n[INFO] Firewall rule '$RuleName' has been successfully created !" -ForegroundColor Green
	}
}

function Main {

	AddPortProxyRule
	AddInboundRule

	$getHostIp = GetHostIP
	$link = "http://" + $getHostIp + ":" + $ListenPort

	do {
		Write-Host "`n[INFO]: Service available at: $link" -ForegroundColor Magenta

		Write-Host "`n   This script creates a bridged connection between the `n   WSL instance and the Host. By pressing 'x' the script `n   will set the settings back to default, breaking the `n   bridged connection and thus your service won't be `n   available from other devices within your LAN." -ForegroundColor Cyan
		Write-Host "`n[Note]: Type 'x' and then press Enter when your done using your service !" -ForegroundColor Yellow
		$option = Read-Host -Prompt " > Option [x]"

		switch ($option) {
			"x" {
				DeletePortProxyRule
				InboundRuleSwitch -SetTrueFalse "False"
			}
			Default {
				Write-Host "`n[WARN] Invalid option !" -ForegroundColor Yellow
			}
		}

	} while ($option -ne "x")
}

# Invoke the Main function
Main