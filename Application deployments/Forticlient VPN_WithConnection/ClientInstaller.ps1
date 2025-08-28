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

    # Hvis header ønskes
    if ($IsHeader) {
        $Log = "################################################################`n         $(Get-Date -Format (Get-Culture).DateTimeFormat.ShortDatePattern) $(Get-Date -UFormat "%T") -> $LogMsg`n################################################################"
    }
    else {
        $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    }

    # Skriv til konsol og logfil
    $Log | Write-Host -ForegroundColor $LogColor
    $Log | Out-File -FilePath $LogFile -Append
}

# Konfigurer konsolens output encoding
$null = cmd /c '' # Tip til ISE
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

# Initialiser log-mappen
$LogPath = "C:\NetIP"
if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Force -Path $LogPath | Out-Null
}

# Logfil
$Script:LogFile = "$LogPath\#DEF_FortiClientInstaller.log" 

# ReadMe-fil med oplysninger
$ReadMeFile = "$LogPath\README.txt"
$ReadMeContent = @"
This folder is used by NetIP to manage all app installations as well as ongoing updates and maintenance. 

##############################################
It must not be deleted under any circumstances.
##############################################
"@

if (!(Test-Path $ReadMeFile)) {
    $ReadMeContent | Out-File -FilePath $ReadMeFile
}

Write-ToLog "Starting installation script" -IsHeader
Write-ToLog "-> Running as: $env:UserName"

###############################################################################
# Installer MSI-fil og verificer installationen
###############################################################################

# Hvis $PSScriptRoot ikke er defineret (fx ved interaktiv kørsel), brug den nuværende mappe.
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptRoot = Get-Location
    Write-ToLog "PSScriptRoot var tom, sat til nuværende mappe: $ScriptRoot"
} else {
    $ScriptRoot = $PSScriptRoot
    Write-ToLog "PSScriptRoot er sat til: $ScriptRoot"
}

# Definér stien til MSI-filen (antager at MSI-filen ligger i samme mappe som scriptet)
$MsiPath = Join-Path -Path $ScriptRoot -ChildPath "FortiClient.msi"
if (-Not (Test-Path $MsiPath)) {
    Write-ToLog "MSI-filen blev ikke fundet: $MsiPath" -LogColor "Red"
    exit 1
}

# Installer MSI-filen via msiexec
try {
    Write-ToLog "Starter installation af MSI: $MsiPath"
    $Arguments = '/i "FortiClient.msi" /qn /norestart'
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -PassThru -ErrorAction Stop

    if ($process.ExitCode -ne 0) {
        Write-ToLog "Installation fejlede med exit kode: $($process.ExitCode)" -LogColor "Red"
        exit $process.ExitCode
    }
    else {
        Write-ToLog "MSI-installation fuldført med exit kode: $($process.ExitCode)"
    }
}
catch {
    Write-ToLog "Fejl under MSI-installation: $($_.Exception.Message)" -LogColor "Red"
    exit 1
}

# Verificer installationen
try {
    # Eksempel på verifikation: tjek om en kendt fil findes
    $InstalledFile = "C:\Program Files\Fortinet\FortiClient\FortiClient.exe"
    if (Test-Path $InstalledFile) {
        Write-ToLog "Verifikation: Installeret fil fundet: $InstalledFile"
    }
    else {
        Write-ToLog "Verifikation mislykkedes: Installeret fil ikke fundet: $InstalledFile" -LogColor "Red"
        exit 1
    }
}
catch {
    Write-ToLog "Fejl under verifikation af installationen: $($_.Exception.Message)" -LogColor "Red"
    exit 1
}

Write-ToLog "Installation og verifikation afsluttet korrekt"

###############################################################################
# Importér VPN-konfiguration fra kundens .reg fil
###############################################################################

$CustomerVPNConnectionName = "DanskErhvervsfinansieringVPN"
$CustomerVPNConfFileName = "DanskErhvervsfinansieringVPN" + ".reg"

try {
    # Definér stien til .reg (antager filen ligger i samme mappe som scriptet)
    $regFile = Join-Path -Path $ScriptRoot -ChildPath $CustomerVPNConfFileName
    if (-not (Test-Path -LiteralPath $regFile)) {
        Write-ToLog "Reg filen blev ikke fundet: $regFile" -LogColor "Red"
        exit 1
    }
    Write-ToLog "Starter import af reg fil: $regFile"

    # Bestem stien til 64-bit reg.exe
    $regExe = "$env:windir\system32\reg.exe"
    if (-not (Test-Path $regExe)) {
        # Hvis vi kører i en 32-bit kontekst, brug sysnative for at få adgang til 64-bit reg.exe
        $regExe = "$env:windir\sysnative\reg.exe"
    }
    Write-ToLog "Bruger reg.exe på: $regExe for import af .reg-filen"

    Start-Process -FilePath $regExe -ArgumentList "import", "`"$regFile`"" -Wait -NoNewWindow -ErrorAction Stop
    Write-ToLog "Reg filen '$regFile' blev importeret succesfuldt."
}
catch {
    Write-ToLog "Fejl under import af reg fil: $($_.Exception.Message)" -LogColor "Red"
    exit 1
}

###############################################################################
# Tjek registry for VPN-tunnel konfiguration
###############################################################################

try {
    # Forventet registreringsnøgle oprettet via .reg filen
    $RegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\$CustomerVPNConnectionName"
    if (Test-Path -LiteralPath $RegPath) {
        Write-ToLog "Registry tjek: VPN tunnel konfiguration fundet: $CustomerVPNConnectionName"
    }
    else {
        Write-ToLog "Registry tjek mislykkedes: VPN tunnel konfiguration ikke fundet: $CustomerVPNConnectionName" -LogColor "Red"
        exit 1
    }
}
catch {
    Write-ToLog "Fejl under registry tjek: $($_.Exception.Message)" -LogColor "Red"
    exit 1
}

Write-ToLog "Ending installation script" -IsHeader