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

function Test-VPNConnectionRegistry {
    param (
        [string]$ConnectionName,
        [string]$Endpoint
    )
    $RegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\$ConnectionName"
    if (Test-Path -LiteralPath $RegPath) {
        try {
            $serverValue = (Get-ItemProperty -Path $RegPath -Name 'server' -ErrorAction SilentlyContinue).server
            if ($serverValue -and $serverValue -eq $Endpoint) {
                Write-ToLog "Registry check: VPN tunnel '$ConnectionName' found and server matches endpoint '$Endpoint'"
                return $true
            } else {
                Write-ToLog "Registry check: VPN tunnel '$ConnectionName' found but server does not match endpoint ('$serverValue' vs '$Endpoint')" "Yellow"
                return $false
            }
        } catch {
            Write-ToLog "Registry check: Error reading server value for '$ConnectionName': $($_.Exception.Message)" "Red"
            return $false
        }
    } else {
        Write-ToLog "Registry check: VPN tunnel configuration not found: $ConnectionName" "Yellow"
        return $false
    }
}
function Test-RegistryValue {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$ConnectionName,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$Endpoint
    )
    $RegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\$ConnectionName"
    try {
        $serverValue = (Get-ItemProperty -Path $RegPath -Name 'server' -ErrorAction Stop).server
        if ($serverValue -and $serverValue -eq $Endpoint) {
            Write-ToLog "Registry check: VPN tunnel '$ConnectionName' found and server matches endpoint '$Endpoint'"
            return $true
        } else {
            Write-ToLog "Registry check: VPN tunnel '$ConnectionName' found but server does not match endpoint ('$serverValue' vs '$Endpoint')" "Yellow"
            return $false
        }
    }
    catch {
        Write-ToLog "Registry check: Error reading server value for '$ConnectionName': $($_.Exception.Message)" "Red"
        return $false
    }
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

Write-ToLog "Starting installation script" -IsHeader
Write-ToLog "Running as: $env:UserName"

# If $PSScriptRoot is not defined (e.g. interactive run), use current folder
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptRoot = Get-Location
    Write-ToLog "PSScriptRoot was empty, set to current folder: $ScriptRoot"
} else {
    $ScriptRoot = $PSScriptRoot
    Write-ToLog "PSScriptRoot is set to: $ScriptRoot"
}

# Pre-installation check for FortiClient and customer VPN connection

if (Test-FortiClientInstallation) {
    Write-ToLog "FortiClient is already installed. Checking for customer VPN connection..."
    # NEW
    if (Test-RegistryValue -ConnectionName -Value "server") {
        Write-ToLog "Customer VPN connection '$Endpoint' is already present in registry. No installation needed." "Green"
        Write-ToLog "Ending installation script" -IsHeader
        exit 0
    } else {
        Write-ToLog "FortiClient is installed, but VPN connection '$Endpoint' is missing. Proceeding with configuration..." "Yellow"
        # Continue to configuration steps below (skip MSI install)
        $SkipMsiInstall = $true
    }
} else {
    Write-ToLog "FortiClient is not installed. Proceeding with MSI installation..."
    $SkipMsiInstall = $false
}

# Define path to MSI file (assume MSI is in same folder as script)
$MsiPath = Join-Path -Path $ScriptRoot -ChildPath "FortiClient.msi"
if (-Not (Test-Path $MsiPath)) {
    Write-ToLog "MSI file not found: $MsiPath" "Red"
    exit 1
}

# Install MSI file via msiexec
if (-not $SkipMsiInstall) {
    try {
        Write-ToLog "Starting MSI installation: $MsiPath"
        $Arguments = '/i "FortiClient.msi" /qn /norestart'
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -PassThru -ErrorAction Stop

        if ($process.ExitCode -ne 0) {
            Write-ToLog "Installation failed with exit code: $($process.ExitCode)" "Red"
            exit $process.ExitCode
        }
        else {
            Write-ToLog "MSI installation completed with exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-ToLog "Error during MSI installation: $($_.Exception.Message)" "Red"
        exit 1
    }

    # Verify installation
    if (-not (Test-FortiClientInstallation)) {
        exit 1
    }
    else {
        Write-ToLog "FortiClient installation verified successfully."
    }
}

Write-ToLog "Disabling default welcome message"
# Disable VPN welcome message
try {
    Set-RegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\Fortinet\FortiClient\Sslvpn' -Name 'show_vpn_welcome' -Type DWord -Value 0
}
catch {
    Write-ToLog "Error disabling VPN welcome message: $($_.Exception.Message)" "Red"
    exit 1
}

# Import VPN configuration from customer .reg file
try {
    # Define path to .reg (assume file is in same folder as script)
    $regFile = Join-Path -Path $ScriptRoot -ChildPath $CustomerVPNConfFileName
    if (-not (Test-Path -LiteralPath $regFile)) {
        Write-ToLog "Reg file not found: $regFile" "Red"
        exit 1
    }
    Write-ToLog "Starting import of reg file: $regFile"

    # Determine path to 64-bit reg.exe
    $regExe = "$env:windir\system32\reg.exe"
    if (-not (Test-Path $regExe)) {
        # If running in 32-bit context, use sysnative to access 64-bit reg.exe
        $regExe = "$env:windir\sysnative\reg.exe"
    }
    Write-ToLog "Using reg.exe at: $regExe for import of .reg file"

    Start-Process -FilePath $regExe -ArgumentList "import", "`"$regFile`"" -Wait -NoNewWindow -ErrorAction Stop
    Write-ToLog "Reg file '$regFile' imported successfully."
}
catch {
    Write-ToLog "Error during reg file import: $($_.Exception.Message)" "Red"
    exit 1
}

# Check registry for VPN tunnel configuration
if (-not (Test-VPNConnectionRegistry -ConnectionName $CustomerVPNConnectionName)) {
    Write-ToLog "Registry check failed: VPN tunnel configuration not found: $CustomerVPNConnectionName" "Red"
    exit 1
}

Write-ToLog "Ending installation script" -IsHeader
#endregion