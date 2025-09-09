#####
# Kundevariabler – tilpas disse værdier til miljøet:
# Placeringen af Fortinet VPN-klienten
$FortinetClientPath = "C:\Program Files\Fortinet\FortiClient\FortiClient.exe"

# Registry-stien til den ønskede VPN-profil (HKLM)
$VPNRegKey = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\DanskErhvervsfinansieringVPN"

# Registry property som tjekkes for at validere VPN-profilen (fx "Description")
$VPNRegProperty = "Description"

# Forventet værdi for registry property "Server"
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
    
    # Opret logfilen, hvis den ikke findes
    if (!(Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
        # Sæt ACL for brugere på logfilen
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

# Konfigurer konsolens output encoding
$null = cmd /c '' # Tip for ISE
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

###############################################################################
# Log mappe og filinitialisering
###############################################################################
$LogPath = "C:\NetIP"    # Tilpas stien, hvis nødvendigt
if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Force -Path $LogPath | Out-Null
}
$Script:LogFile = "$LogPath\#FortinetVPN_Detection.log"

$ReadMeFile = "$LogPath\README.txt"
$ReadMeContent = @"
Denne mappe anvendes af NetIP til at styre installationer og opdateringer.

##############################################
Må ikke slettes under nogen omstændigheder.
##############################################
"@
if (!(Test-Path $ReadMeFile)) {
    $ReadMeContent | Out-File -FilePath $ReadMeFile
}

Write-ToLog "Starting Fortinet VPN detection script" -IsHeader
Write-ToLog "-> Running as: $env:UserName"

###############################################################################
# Test om Fortinet VPN-klienten er installeret
###############################################################################
if (Test-Path -Path $FortinetClientPath) {
    Write-ToLog "Fortinet VPN klient fundet på: $FortinetClientPath" "Green"
} else {
    Write-ToLog "Fortinet VPN klient ikke fundet på: $FortinetClientPath" "Red"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationNotDetected
}

###############################################################################
# Test om den korrekte VPN profil findes i registry (HKLM)
###############################################################################
if (Test-RegistryValue -Path $VPNRegKey -Value $VPNRegProperty) {
    Write-ToLog "VPN profil fundet i registreringsdatabasen: $VPNRegKey" "Green"

    # Tjek om registry-værdien "Server" er korrekt
    try {
        $ActualServer = (Get-ItemProperty -Path $VPNRegKey -Name "Server" -ErrorAction Stop).Server
        if ($ActualServer -eq $ExpectedVPNServer) {
            Write-ToLog "Registry tjek: Server-værdien er korrekt: $ActualServer" "Green"
            Write-ToLog "Ending detection script" -IsHeader
            ApplicationDetected
        }
        else {
            Write-ToLog "Registry tjek: Server-værdien er forkert. Forventet: $ExpectedVPNServer, fundet: $ActualServer" "Red"
            Write-ToLog "Ending detection script" -IsHeader
            ApplicationNotDetected
        }
    }
    catch {
        Write-ToLog "Fejl under aflæsning af Server-værdien: $($_.Exception.Message)" "Red"
        Write-ToLog "Ending detection script" -IsHeader
        ApplicationNotDetected
    }
}
else {
    Write-ToLog "VPN profil ikke fundet i registreringsdatabasen: $VPNRegKey" "Red"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationNotDetected
}
