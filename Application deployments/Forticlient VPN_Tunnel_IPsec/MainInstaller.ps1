#region ---------------------------------------------------[Script parameters]-----------------------------------------------------
param(
[Parameter(Mandatory=$false)][string]$Prefix,
[Parameter(Mandatory=$false)][string]$VpnConfFileName,
[Parameter(Mandatory=$false)][string]$Endpoint,
[Parameter(Mandatory=$false)][string]$ExpectedClientVersion
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

function Get-FortiClientVersion {
    [CmdletBinding()]
    param(
        [string]$ExePath = "C:\Program Files\Fortinet\FortiClient\FortiClient.exe"
    )
    try {
        if (Test-Path -LiteralPath $ExePath) {
            return (Get-Item -LiteralPath $ExePath).VersionInfo.ProductVersion
        }
        return $null
    } catch {
        Write-ToLog "Failed to read FortiClient version: $($_.Exception.Message)" "Yellow"
        return $null
    }
}

function Get-MsiProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Property
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database  = $installer.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$installer,@($Path,0))
        $query     = "SELECT Value FROM Property WHERE Property='$Property'"
        $view      = $database.OpenView($query)
        $view.Execute()
        $record = $view.Fetch()
        if ($record) { return $record.StringData(1) }
        return $null
    } catch {
        Write-ToLog "Failed to read MSI property '$Property' from '$Path': $($_.Exception.Message)" "Yellow"
        return $null
    }
}

function Get-MsiProductVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    return Get-MsiProperty -Path $Path -Property 'ProductVersion'
}
# Helper: Open 64-bit HKLM base key once (for registry operations despite possible 32-bit host)
function Open-Hklm64BaseKey {
    [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
}

function Test-RegistryKey64 {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$RelativePath)
    try {
        $base = Open-Hklm64BaseKey
        return [bool]($base.OpenSubKey($RelativePath))
    } catch { return $false }
}

function Get-RegistryValue64 {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Path,   # Accept full HKLM:\ path OR relative without HKLM:\
        [Parameter(Mandatory)][string]$Name
    )
    try {
        $rel = $Path -replace '^HKLM:\\',''
        $base = Open-Hklm64BaseKey
        $k = $base.OpenSubKey($rel)
        if (-not $k) { return $null }
        return $k.GetValue($Name,$null)
    } catch { return $null }
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
if ($ExpectedClientVersion) { Write-ToLog "We expect client version: $ExpectedClientVersion" }

# If $PSScriptRoot is not defined, use current folder
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptRoot = Get-Location
    Write-ToLog "PSScriptRoot was empty, set to current folder: $ScriptRoot"
} else {
    $ScriptRoot = $PSScriptRoot
    Write-ToLog "PSScriptRoot is set to: $ScriptRoot"
}

# Pre-install version (if present)
$preVersion = Get-FortiClientVersion
if ($preVersion) { $preVersion = $preVersion.Trim() }
if ($preVersion) {
    Write-ToLog "We found existing FortiClient version: $preVersion"
} else {
    Write-ToLog "FortiClient version not detected prior to install"
}

## -------------------------------------------------- Version Enforcement Logic --------------------------------------------------

$msi = Get-ChildItem -Path $ScriptRoot -Filter 'FortiClient*.msi' -File -ErrorAction SilentlyContinue

$msiVersion = Get-MsiProductVersion -Path $msi.FullName
if (-not $msiVersion) {
    Write-ToLog "Could not read ProductVersion from $($Msi.Name). Proceeding with installation anyway." 'Yellow'
}
$displayMsiVersion = if ($msiVersion) { $msiVersion } else { 'n/a' }
Write-ToLog "Forticlient installer found in scriptroot: $($Msi.Name) Version => $displayMsiVersion"

$installedVersion = $preVersion
$expectedTrim = if ([string]::IsNullOrWhiteSpace($ExpectedClientVersion)) { $null } else { $ExpectedClientVersion.Trim() }
$needInstall = $true

if ($expectedTrim) {
    if ($installedVersion -and $msiVersion -and ($installedVersion.Trim() -eq $expectedTrim) -and ($msiVersion -eq $expectedTrim)) {
        Write-ToLog "All versions match version '$expectedTrim' Skipping reinstall" 'Green'
        $needInstall = $false
    } else {
        # Determine reasons
        if (-not $installedVersion) { Write-ToLog "FortiClient not installed; will now install '$expectedTrim'." 'Yellow' }
        if ($installedVersion -and $installedVersion.Trim() -ne $expectedTrim) { Write-ToLog "Installed version '$installedVersion' does not match the expected version '$expectedTrim'. Install continues" 'Yellow' }
        if ($msiVersion -and $msiVersion -ne $expectedTrim) { Write-ToLog "MSI version in scriptroot is '$msiVersion', which does not match the expected version '$expectedTrim'." 'Yellow' }
        if (-not $msiVersion) { Write-ToLog "MSI ProductVersion unreadable; proceeding by policy to install." 'Yellow' }
    }
} else {
    # No expectation supplied: only install if missing
    if ($installedVersion) {
        Write-ToLog "No Expected Client Version supplied and FortiClient already installed ($installedVersion) Skipping reinstall" 'Green'
        $needInstall = $false
    } else {
        Write-ToLog 'No Expected Client Version supplied; FortiClient absent. Installing.' 'Yellow'
    }
}

if ($needInstall) {
    Write-ToLog 'Starting MSI installation' 'Yellow'
    try {
        Write-ToLog "Starting MSI installation: $($Msi.FullName)"
        $Arguments = "/i `"$($Msi.FullName)`" /qn /norestart"
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $Arguments -Wait -PassThru -ErrorAction Stop
        $exitCode = $process.ExitCode
        switch ($exitCode) {
            0     { Write-ToLog "MSI installation completed successfully"; break }
            3010  { Write-ToLog "MSI installation completed (exit code 3010: restart required). Treating as success." 'Yellow'; break }
            default {
                Write-ToLog "Installation failed with exit code: $exitCode" 'Red'
                exit $exitCode
            }
        }
    } catch {
        Write-ToLog "Error during MSI installation: $($_.Exception.Message)" 'Red'
        exit 1
    }

    if (-not (Test-FortiClientInstallation)) {
        Write-ToLog 'Post-install verification failed' 'Red'
        exit 1
    } else {
        Write-ToLog 'FortiClient installation verified successfully.' 'Green'
    }
}

# Post-install / final version logging
$postVersion = Get-FortiClientVersion
if ($postVersion) {
    if ($needInstall) {
        Write-ToLog "Forticlient version after installation: $postVersion"
    } else {
        Write-ToLog "No installation was performed; current version is $postVersion"
    }
} 
else {
    Write-ToLog "Forticlient version still not detectable after installation attempt." "Yellow"
}

# ---------------------------------------------------------------------------
# VPN Tunnel Enforcement (always re-apply .reg file)
# ---------------------------------------------------------------------------

# Import VPN configuration from customer .reg file
try {
    # Define path to .reg (assume file is in same folder as script)
    $regFile = Join-Path -Path $ScriptRoot -ChildPath $VpnConfFileName
    if (-not (Test-Path -LiteralPath $regFile)) {
        Write-ToLog "Reg file not found: $regFile" "Red"
        exit 1
    }
    Write-ToLog "Starting import of reg file: $regFile"

    $regExe = Join-Path $env:windir 'System32\reg.exe'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $regExe = Join-Path $env:windir 'sysnative\reg.exe'
    }
    Write-ToLog "Using reg.exe at: $regExe for import of .reg file"

    Start-Process -FilePath $regExe -ArgumentList "import", "`"$regFile`"" -Wait -NoNewWindow -ErrorAction Stop
    Write-ToLog "Reg file '$regFile' imported successfully."
}
catch {
    Write-ToLog "Error during reg file import: $($_.Exception.Message)" "Red"
    exit 1
}

# ----------------------- 64-bit registry verification (refactored) -----------------------
$tunnelRelative = "SOFTWARE\Fortinet\FortiClient\ipsec\Tunnels\$Prefix"
if (-not (Test-RegistryKey64 -RelativePath $tunnelRelative)) {
    Write-ToLog "Registry check (64-bit) failed: $tunnelRelative" -LogColor Red
    Write-ToLog "Ending installation script" -IsHeader
    exit 1
} else {
    Write-ToLog "Registry check (64-bit) succeeded: $tunnelRelative"
}

# Post-import validation of Server value (if Endpoint supplied)
if (-not [string]::IsNullOrWhiteSpace($Endpoint)) {
    $serverValue = Get-RegistryValue64 -Path "HKLM:\SOFTWARE\Fortinet\FortiClient\ipsec\Tunnels\$Prefix\P1" -Name 'RemoteGW'
    if ($null -eq $serverValue) {
        Write-ToLog "Could not read Server value after import (64-bit hive)." 'Red'
        Write-ToLog "Ending installation script" -IsHeader
        exit 1
    } elseif ($serverValue -ne $Endpoint) {
        Write-ToLog "Post-import validation FAILED: Server='$serverValue' != Expected '$Endpoint'" 'Red'
        Write-ToLog "Ending installation script" -IsHeader
        exit 1
    } else {
        Write-ToLog "Post-import validation succeeded: Server matches Endpoint ($Endpoint)" 'Green'
    }
}

Write-ToLog "Ending installation script" -IsHeader

#endregion