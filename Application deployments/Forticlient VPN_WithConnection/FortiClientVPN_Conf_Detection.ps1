#####
# Customer variables – adjust these values to your environment:
# Location of the Fortinet VPN client
$FortinetClientPath = "C:\Program Files\Fortinet\FortiClient\FortiClient.exe"

# Registry path to the desired VPN profile (HKLM)
$VPNRegKey = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\DanskErhvervsfinansieringVPN"

# Registry property checked to validate the VPN profile (e.g., "Description")
$VPNRegProperty = "Description"

# Expected value for registry property "Server"
$ExpectedVPNServer = "vpn.dansk-erhvervsfinansiering.dk:443"
#####

function Test-RegistryValue {
    param (
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$Path,
    
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$Value
    )
    try {
        Get-ItemProperty -Path $Path | Select-Object -ExpandProperty $Value -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function ApplicationDetected {
    Write-Host "Fortinet VPN klient med korrekt VPN profil er installeret."
    exit 0
}

function ApplicationNotDetected {
    exit 1
}

function Write-ToLog {
    [CmdletBinding()]
    param(
        [Parameter()] [String] $LogMsg,
        [Parameter()] [String] $LogColor = "White",
        [Parameter()] [Switch] $IsHeader = $false
    )
    
    # Create the log file if it does not exist
    if (!(Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
        # Set ACL for users on the log file
        $NewAcl = Get-Acl -Path $LogFile
        $identity = New-Object System.Security.Principal.SecurityIdentifier S-1-5-11
        $fileSystemRights = "Modify"
        $type = "Allow"
        $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
        $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
        $NewAcl.SetAccessRule($fileSystemAccessRule)
        Set-Acl -Path $LogFile -AclObject $NewAcl
    }
    
    if ($IsHeader) {
        $Log = "################################################################`n         $(Get-Date -Format (Get-Culture).DateTimeFormat.ShortDatePattern) $(Get-Date -UFormat "%T") -> $LogMsg`n################################################################"
    }
    else {
        $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    }
    
    $Log | Write-Host -ForegroundColor $LogColor
    $Log | Out-File -FilePath $LogFile -Append
}

# Configure console output encoding
$null = cmd /c '' # Tip for ISE
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

###############################################################################
# Log folder and file initialization
###############################################################################
$LogPath = "C:\NetIP"    # Adjust the path if necessary
if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Force -Path $LogPath | Out-Null
}
$Script:LogFile = "$LogPath\#FortinetVPN_Detection.log"

$ReadMeFile = "$LogPath\README.txt"
$ReadMeContent = @"
This folder is used by NetIP to manage installations and updates.

##############################################
Do not delete under any circumstances.
##############################################
"@
if (!(Test-Path $ReadMeFile)) {
    $ReadMeContent | Out-File -FilePath $ReadMeFile
}

Write-ToLog "Starting Fortinet VPN detection script" -IsHeader
Write-ToLog "-> Running as: $env:UserName"

###############################################################################
# Check if Fortinet VPN client is installed
###############################################################################
if (Test-Path -Path $FortinetClientPath) {
    Write-ToLog "Fortinet VPN client found at: $FortinetClientPath" "Green"
} else {
    Write-ToLog "Fortinet VPN client not found at: $FortinetClientPath" "Red"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationNotDetected
}

###############################################################################
# Check if the correct VPN profile exists in the registry (HKLM)
###############################################################################
if (Test-RegistryValue -Path $VPNRegKey -Value $VPNRegProperty) {
    Write-ToLog "VPN profile found in registry: $VPNRegKey" "Green"

    # Check if the registry value "Server" is correct
    try {
        $ActualServer = (Get-ItemProperty -Path $VPNRegKey -Name "Server" -ErrorAction Stop).Server
        if ($ActualServer -eq $ExpectedVPNServer) {
            Write-ToLog "Registry check: Server value is correct: $ActualServer" "Green"
            Write-ToLog "Ending detection script" -IsHeader
            ApplicationDetected
        }
        else {
            Write-ToLog "Registry check: Server value is incorrect. Expected: $ExpectedVPNServer, found: $ActualServer" "Red"
            Write-ToLog "Ending detection script" -IsHeader
            ApplicationNotDetected
        }
    }
    catch {
        Write-ToLog "Error reading Server value: $($_.Exception.Message)" "Red"
        Write-ToLog "Ending detection script" -IsHeader
        ApplicationNotDetected
    }
}
else {
    Write-ToLog "VPN profile not found in registry: $VPNRegKey" "Red"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationNotDetected
}
