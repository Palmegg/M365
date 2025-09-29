#region ---------------------------------------------------[Script parameters]-----------------------------------------------------
param(
[Parameter(Mandatory=$false)][string]$Prefix,
[Parameter(Mandatory=$false)][string]$VpnConfFileName,
[Parameter(Mandatory=$false)][string]$Endpoint,
[Parameter(Mandatory=$false)][string]$ExpectedVpnVersion,
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

# Enumerate FortiClient uninstall entries (64 + 32-bit views)
function Get-FortiClientUninstallEntries {
    $paths = @(
        'HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $results = @()
    foreach ($p in $paths) {
        try {
            if (Test-Path $p) {
                Get-ChildItem -Path $p -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $dn = (Get-ItemProperty -Path $_.PSPath -ErrorAction Stop).DisplayName
                        if ($dn -and $dn -like 'FortiClient*') {
                            $ip = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                            $uninst = $ip.UninstallString
                            $quiet  = $ip.QuietUninstallString
                            $prodCode = $null
                            foreach ($cmd in @($uninst,$quiet)) {
                                if (-not $prodCode -and $cmd -match '\{[0-9A-Fa-f\-]{36}\}') { $prodCode = $Matches[0] }
                            }
                            $results += [pscustomobject]@{
                                DisplayName   = $dn
                                UninstallString = $uninst
                                QuietUninstallString = $quiet
                                ProductCode   = $prodCode
                                RegistryPath  = $_.PSPath
                            }
                        }
                    } catch {}
                }
            }
        } catch {}
    }
    # Deduplicate by ProductCode if present
    $dedup = @{}
    foreach ($r in $results) {
        $key = if ($r.ProductCode) { $r.ProductCode } else { $r.RegistryPath }
        if (-not $dedup.ContainsKey($key)) { $dedup[$key] = $r }
    }
    return $dedup.Values
}

function Uninstall-FortiClientExisting {
    $entries = Get-FortiClientUninstallEntries
    if (-not $entries -or $entries.Count -eq 0) {
        Write-ToLog 'No FortiClient uninstall entries found; nothing to remove.' 'Yellow'
        return $true
    }
    Write-ToLog ("Found {0} FortiClient uninstall entr{1}. Beginning removal." -f $entries.Count, ($(if($entries.Count -eq 1){'y'}else{'ies'}))) 'Yellow'
    foreach ($e in $entries) {
        $pc = $e.ProductCode
        $desc = if ($pc) { "$($e.DisplayName) $pc" } else { $e.DisplayName }
        $args = $null
        if ($pc) {
            $args = "/x $pc /qn /norestart"
        } elseif ($e.UninstallString -and $e.UninstallString -match 'MsiExec(\.exe)?\s+/I\s*\{') {
            # Replace /I with /X and force silent
            $prod = $null; if ($e.UninstallString -match '\{[0-9A-Fa-f\-]{36}\}') { $prod = $Matches[0] }
            if ($prod) { $args = "/x $prod /qn /norestart" }
        }
        if (-not $args) {
            # Fallback: attempt quiet uninstall string if provided
            if ($e.QuietUninstallString) {
                Write-ToLog "Executing provided QuietUninstallString for $desc" 'Yellow'
                try {
                    Start-Process -FilePath 'cmd.exe' -ArgumentList "/c", $e.QuietUninstallString -Wait -WindowStyle Hidden
                } catch {
                    Write-ToLog "Failed quiet uninstall for $desc $($_.Exception.Message)" 'Red'
                    return $false
                }
                continue
            } else {
                Write-ToLog "Unable to derive silent uninstall command for $desc (skipping)." 'Red'
                return $false
            }
        }
        Write-ToLog "Uninstalling $desc via msiexec $args"
        try {
            $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru -ErrorAction Stop
            $code = $proc.ExitCode
            switch ($code) {
                0     { Write-ToLog "Uninstall succeeded for $desc" 'Green' }
                3010  { Write-ToLog "Uninstall succeeded for $desc (3010: restart required)" 'Yellow' }
                1605  { Write-ToLog "Product already uninstalled (1605) for $desc" 'Yellow' }
                default {
                    Write-ToLog "Uninstall failed for $desc (exit code $code)" 'Red'
                    return $false
                }
            }
        } catch {
            Write-ToLog "Exception during uninstall of $desc $($_.Exception.Message)" 'Red'
            return $false
        }
    }
    return $true
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
if ($ExpectedVpnVersion) { Write-ToLog "ExpectedVpnVersion provided: $ExpectedVpnVersion" }
if ($ExpectedClientVersion) { Write-ToLog "ExpectedClientVersion provided: $ExpectedClientVersion" }

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
    Write-ToLog "Detected existing FortiClient version before install attempt: $preVersion"
} else {
    Write-ToLog "FortiClient version not detected prior to install (likely not installed)."
}

## -------------------------------------------------- Version Enforcement Logic --------------------------------------------------

$msiFiles = Get-ChildItem -Path $ScriptRoot -Filter 'FortiClient*.msi' -File -ErrorAction SilentlyContinue
if (-not $msiFiles -or $msiFiles.Count -eq 0) {
    Write-ToLog "No FortiClient*.msi file found in $ScriptRoot" 'Red'
    exit 1
}
if ($msiFiles.Count -gt 1) {
    Write-ToLog "Multiple FortiClient MSIs detected (expected exactly one): $($msiFiles.Name -join ', ')" 'Red'
    Write-ToLog 'Aborting because only a single MSI is allowed by current policy.' 'Red'
    exit 1
}

$Msi = $msiFiles[0]
$msiVersion = Get-MsiProductVersion -Path $Msi.FullName
if (-not $msiVersion) {
    Write-ToLog "Could not read ProductVersion from $($Msi.Name). Proceeding with installation anyway." 'Yellow'
}
$displayMsiVersion = if ($msiVersion) { $msiVersion } else { 'n/a' }
Write-ToLog "Found FortiClient MSI: $($Msi.Name) (ProductVersion: $displayMsiVersion)"

$installedVersion = $preVersion
$expectedTrim = if ([string]::IsNullOrWhiteSpace($ExpectedClientVersion)) { $null } else { $ExpectedClientVersion.Trim() }

# Decision matrix:
# Skip ONLY if all three values that exist align: ExpectedClientVersion == InstalledVersion == MSI ProductVersion.
# If ExpectedClientVersion is provided and any mismatch with installed OR MSI version -> uninstall existing (if any) then install MSI.
# If ExpectedClientVersion not provided, just install if not installed (leave existing if present already).

$needInstall = $true
$needUninstallFirst = $false

if ($expectedTrim) {
    if ($installedVersion -and $msiVersion -and ($installedVersion.Trim() -eq $expectedTrim) -and ($msiVersion -eq $expectedTrim)) {
        Write-ToLog "All versions match ExpectedClientVersion '$expectedTrim'. Skipping reinstall." 'Green'
        $needInstall = $false
    } else {
        # Determine reasons
        if (-not $installedVersion) { Write-ToLog "FortiClient not installed; will install expected version '$expectedTrim'." 'Yellow' }
        if ($installedVersion -and $installedVersion.Trim() -ne $expectedTrim) { Write-ToLog "Installed version '$installedVersion' != Expected '$expectedTrim' (will enforce)." 'Yellow'; $needUninstallFirst = $true }
        if ($msiVersion -and $msiVersion -ne $expectedTrim) { Write-ToLog "MSI ProductVersion '$msiVersion' != Expected '$expectedTrim' (still proceeding to install—assuming MSI is authoritative)." 'Yellow' }
        if (-not $msiVersion) { Write-ToLog "MSI ProductVersion unreadable; proceeding by policy to install." 'Yellow' }
    }
} else {
    # No expectation supplied: only install if missing
    if ($installedVersion) {
        Write-ToLog "No ExpectedClientVersion supplied and FortiClient already installed ($installedVersion). Skipping reinstall." 'Green'
        $needInstall = $false
    } else {
        Write-ToLog 'No ExpectedClientVersion supplied; FortiClient absent. Installing.' 'Yellow'
    }
}

if ($needInstall) {
    if ($needUninstallFirst) {
        Write-ToLog 'Beginning uninstall of existing FortiClient versions before reinstall.' 'Yellow'
        if (-not (Uninstall-FortiClientExisting)) {
            Write-ToLog 'Uninstall phase reported errors; aborting.' 'Red'
            exit 1
        }
    }
    try {
        Write-ToLog "Starting MSI installation: $($Msi.FullName)"
        $Arguments = "/i `"$($Msi.FullName)`" /qn /norestart"
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $Arguments -Wait -PassThru -ErrorAction Stop
        $exitCode = $process.ExitCode
        switch ($exitCode) {
            0     { Write-ToLog "MSI installation completed successfully (exit code 0)"; break }
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
        Write-ToLog 'Post-install verification failed (FortiClient executable missing)' 'Red'
        exit 1
    } else {
        Write-ToLog 'FortiClient installation verified successfully.' 'Green'
    }
}

# Post-install / final version logging
$postVersion = Get-FortiClientVersion
if ($postVersion) {
    Write-ToLog "Final FortiClient version detected: $postVersion"
} else {
    Write-ToLog "FortiClient version still not detectable after installation attempt." "Yellow"
}

# ---------------------------------------------------------------------------
# VPN Tunnel Enforcement (always re-apply .reg file)
# ---------------------------------------------------------------------------

# Import VPN configuration from customer .reg file (always enforce desired state)
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
$tunnelRelative = "SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\$Prefix"
if (-not (Test-RegistryKey64 -RelativePath $tunnelRelative)) {
    Write-ToLog "Registry check (64-bit) failed: $tunnelRelative" -LogColor Red
    Write-ToLog "Ending installation script" -IsHeader
    exit 1
} else {
    Write-ToLog "Registry check (64-bit) succeeded: $tunnelRelative"
}

# Post-import validation of Server value (if Endpoint supplied)
if (-not [string]::IsNullOrWhiteSpace($Endpoint)) {
    $serverValue = Get-RegistryValue64 -Path "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\$Prefix" -Name 'Server'
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

# Set InstalledVersion in registry for version control (only if provided)
$TunnelRegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\$Prefix"
if (-not [string]::IsNullOrWhiteSpace($ExpectedVpnVersion)) {
    try {
        Set-ItemProperty -Path $TunnelRegPath -Name 'InstalledVersion' -Value $ExpectedVpnVersion -Type String
        Write-ToLog "Set InstalledVersion to $ExpectedVpnVersion in $TunnelRegPath"
    } catch {
        Write-ToLog "Failed to set InstalledVersion in registry: $($_.Exception.Message)" 'Red'
        Write-ToLog "Ending installation script" -IsHeader
        exit 1
    }
} else {
    Write-ToLog 'ExpectedVpnVersion not provided; InstalledVersion not updated.' 'Yellow'
}

Write-ToLog "Ending installation script" -IsHeader

#endregion