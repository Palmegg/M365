#region ---------------------------------------------------[Script parameters]-----------------------------------------------------
param(
[Parameter(Mandatory=$false)][string]$Prefix,
[Parameter(Mandatory=$false)][string]$VpnConnectionDescription,
[Parameter(Mandatory=$false)][string]$VpnConfFileName,
[Parameter(Mandatory=$false)][string]$Endpoint
)

#endregion

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$CorpDataPath                 = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName           = "#${Prefix}_ForticlientInstaller"
[string]$VpnConfFileName              = "$VpnConfFileName.reg"
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

    #Create file if doesn't exist
    if (!(Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
    }

    #If header requested
    if ($IsHeader) {
        $Log = "################################################################`n         $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) $(Get-Date -UFormat "%T")  $LogMsg`n################################################################"
    }
    else {
        $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    }

    #Echo log
    $Log | Write-host -ForegroundColor $LogColor

    #Write log to file
    $Log | Out-File -FilePath $LogFile -Append
}

function Set-RegistryKey {
    param(
        [Parameter(Mandatory=$true)] [string]$Key,
        [Parameter(Mandatory=$true)] [string]$Name,
        [Parameter(Mandatory=$true)] [string]$Type,
        [Parameter(Mandatory=$true)] $Value
    )
    try {
        $regPath = $Key -replace 'HKEY_LOCAL_MACHINE', 'HKLM:'
        if (!(Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        if ($Type -eq 'DWord') {
            if (Get-ItemProperty -Path $regPath -Name $Name -ErrorAction SilentlyContinue) {
                Set-ItemProperty -Path $regPath -Name $Name -Value ([int]$Value) -Type DWord
            } else {
                New-ItemProperty -Path $regPath -Name $Name -Value ([int]$Value) -PropertyType DWord -Force | Out-Null
            }
        } else {
            # Add support for other types if needed
            Set-ItemProperty -Path $regPath -Name $Name -Value $Value
        }
        Write-ToLog "Registry key $Key, value $Name set to $Value"
    }
    catch {
        Write-ToLog "Error setting registry key: $($_.Exception.Message)" "Red"
        exit 1
    }
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
function Test-RegistryValue {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$Endpoint
    )
    $RegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\$Prefix"
    try {
        $serverValue = (Get-ItemProperty -Path $RegPath -Name 'server' -ErrorAction Stop).server
        if ($serverValue -eq $Endpoint) {
            Write-ToLog "Registry check: VPN tunnel '$Endpoint' found and server matches endpoint '$Endpoint'"
            return $true
        } else {
            Write-ToLog "Registry check: VPN tunnel '$Endpoint' found but server does not match endpoint ('$serverValue' vs '$Endpoint')" "Yellow"
            return $false
        }
    }
    catch {
        Write-ToLog "Registry check: Error reading server value for '$ConnectionName': $($_.Exception.Message)" "Red"
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
#endregion

#region ---------------------------------------------------[Script Execution]------------------------------------------------------

#Configure console output encoding
$null = cmd /c '' #Tip for ISE
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

# ReadMe file with disclaimer and instructions
$ReadMeFile = "$logpath\README.txt"
$ReadMeContent = @"
This folder is used to manage all app installations as well as ongoing updates and maintenance. 

##############################################
It must not be deleted under any circumstances.
##############################################
"@

# Create ReadMe file if it doesn't exist
if (!(Test-Path $ReadMeFile)) {
    $ReadMeContent | Out-File -FilePath $ReadMeFile
}

Write-ToLog "Starting detection script" -IsHeader
Write-ToLog "Running as: $env:UserName"

###############################################################################
# Test om Fortinet VPN-klienten er installeret
###############################################################################
if (Test-FortiClientInstallation) {

    Write-ToLog "FortiClient is installed. Checking for VPN profile..."
    if (Test-RegistryValue -Endpoint $Endpoint) {
    Write-ToLog "VPN connection '$Endpoint' found" "Green"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationDetected
    } else {
    Write-ToLog "Registry check failed: VPN tunnel configuration not found: '$Endpoint' is missing." "Red"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationNotDetected
}
}
else {
    Write-ToLog "FortiClient is not installed." "Red"
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
