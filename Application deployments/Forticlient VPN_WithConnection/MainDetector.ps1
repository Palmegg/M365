#region ---------------------------------------------------[Script parameters]-----------------------------------------------------
param(
    [Parameter(Mandatory=$false)][string]$Prefix,
    [Parameter(Mandatory=$false)][string]$ExpectedVersion = "1.0"
)
#endregion

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$CorpDataPath                 = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName           = "#${Prefix}_ForticlientInstaller"
#endregion

#region ---------------------------------------------------[Static Variables]------------------------------------------------------
[string]$logpath = "$($CorpDataPath)"
if (!(Test-Path -Path $logpath)) {
    New-Item -Path $logpath -ItemType Directory -Force | Out-Null
}
[string]$Script:LogFile = "$($logpath)\$($ApplicationLogName).log"
#endregion

#region ---------------------------------------------------[Functions]-------------------------------------------------------------
function Write-ToLog {
    [CmdletBinding()]
    param(
        [Parameter()] [String] $LogMsg,
        [Parameter()] [String] $LogColor = "White",
        [Parameter()] [Switch] $IsHeader = $false
    )

    if (!(Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
    }

    if ($IsHeader) {
        $Log = "################################################################`n         $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) $(Get-Date -UFormat "%T")  $LogMsg`n################################################################"
    }
    else {
        $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    }

    $Log | Write-host -ForegroundColor $LogColor
    $Log | Out-File -FilePath $LogFile -Append
}

function Test-FortiClientInstallation {
    param (
        [string]$InstalledFile = "C:\Program Files\Fortinet\FortiClient\FortiClient.exe"
    )
    try {
        if (Test-Path $InstalledFile) {
            Write-ToLog "Verification: Installed file found: $InstalledFile"
            return $true
        }
        else {
            Write-ToLog "Verification failed: Installed file not found: $InstalledFile" "Red"
            return $false
        }
    }
    catch {
        Write-ToLog "Error during installation verification: $($_.Exception.Message)" "Red"
        return $false
    }
}

function ApplicationDetected {
    Write-Host "Fortinet VPN client with correct VPN profile is installed."
    exit 0
}

function ApplicationNotDetected {
    exit 1
}
#endregion

#region ---------------------------------------------------[Script Execution]------------------------------------------------------

$null = cmd /c '' #Tip for ISE
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

$ReadMeFile = "$logpath\README.txt"
$ReadMeContent = @"
This folder is used to manage all app installations as well as ongoing updates and maintenance. 

##############################################
It must not be deleted under any circumstances.
##############################################
"@

if (!(Test-Path $ReadMeFile)) {
    $ReadMeContent | Out-File -FilePath $ReadMeFile
}

Write-ToLog "Starting detection script" -IsHeader
Write-ToLog "Running as: $env:UserName"

###############################################################################
# Detection logic: Check FortiClient and InstalledVersion in registry
###############################################################################
if (Test-FortiClientInstallation) {
    Write-ToLog "FortiClient is installed. Checking for VPN tunnel version..."

    $TunnelRegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\$Prefix"
    try {
        $installedVersion = (Get-ItemProperty -Path $TunnelRegPath -Name "InstalledVersion" -ErrorAction Stop).InstalledVersion
        if ($installedVersion -eq $ExpectedVersion) {
            Write-ToLog "InstalledVersion matches ExpectedVersion ($ExpectedVersion)." "Green"
            Write-ToLog "Ending detection script" -IsHeader
            ApplicationDetected
        } else {
            Write-ToLog "InstalledVersion ($installedVersion) does not match ExpectedVersion ($ExpectedVersion)." "Red"
            Write-ToLog "Ending detection script" -IsHeader
            ApplicationNotDetected
        }
    } catch {
        Write-ToLog "Could not read InstalledVersion from registry: $($_.Exception.Message)" "Red"
        Write-ToLog "Ending detection script" -IsHeader
        ApplicationNotDetected
    }
} else {
    Write-ToLog "FortiClient is not installed." "Red"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationNotDetected
}
#endregion