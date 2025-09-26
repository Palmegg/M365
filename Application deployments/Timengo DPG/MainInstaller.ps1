#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$Prefix                         = "TimengoDPG"
[string]$TargetVersion                  = "7.34.0.0"
[string]$MsiName                        = "DPGAddin*.msi"
[string]$RegFileName                    = "Kombit_DPGSettings.reg"
[string]$CorpDataPath                   = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName             = "#${Prefix}"
[string]$RegistryPath                   = "HKLM:\SOFTWARE\Timengo\DPGAddIn"
[string]$RegistryValueName              = "RESTurl"
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
    } else {
        $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    }
    $Log | Write-Host -ForegroundColor $LogColor
    $Log | Out-File -FilePath $LogFile -Append
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

# Ensure we are running in 64-bit PowerShell (Intune often launches 32-bit). Relaunch via SysNative if needed.
if ($env:PROCESSOR_ARCHITEW6432 -and -not [Environment]::Is64BitProcess) {
    Write-ToLog "Detected 32-bit PowerShell on 64-bit OS; relaunching script in 64-bit context for correct registry hive access." 'Yellow'
    $sysNativePwsh = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    & $sysNativePwsh -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

function Test-RegistryValue64 {
    <#
        Returns $true if the specified value exists in the 64-bit HKLM view (even when invoked from a 32-bit host).
        Path should be like HKLM:\SOFTWARE\Vendor\Key
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    try {
        $subPath = $Path -replace '^HKLM:\\',''
        $base64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
        $key = $base64.OpenSubKey($subPath)
        if (-not $key) { return $false }
        $val = $key.GetValue($Name,$null)
        return ($null -ne $val)
    } catch {
        return $false
    }
}

#region -------------------------[ Helper: Detect & Uninstall Other Installed Versions ]-------------------------------------------
function Get-DpgInstalledProducts {
    <#
        Returns uninstall registry entries that appear related to the Timengo DPG Add-In
        (heuristic based on DisplayName containing 'DPG' and 'Add' / 'Add-In').
    #>
    [CmdletBinding()]
    param()
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $results = @()
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                $dn = $p.DisplayName
                if ([string]::IsNullOrWhiteSpace($dn)) { return }
                if ($dn -match '(?i)DPG' -and ($dn -match '(?i)Add')) {
                    $results += [pscustomobject]@{
                        DisplayName     = $dn
                        DisplayVersion  = $p.DisplayVersion
                        UninstallString = $p.UninstallString
                        PSPath          = $_.PSPath
                    }
                }
            } catch {}
        }
    }
    return $results
}

function Uninstall-DpgOtherVersions {
    <#
        Uninstalls any detected DPG Add-In product whose DisplayVersion differs from target version.
        Falls back to parsing ProductCode GUID from UninstallString. Accepts exit codes 0, 3010, 1605 as success.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetVersion
    )
    if ([string]::IsNullOrWhiteSpace($TargetVersion)) {
        Write-ToLog "TargetVersion not supplied to Uninstall-DpgOtherVersions; skipping cleanup." 'Yellow'
        return
    }
    $installed = Get-DpgInstalledProducts
    if (-not $installed -or $installed.Count -eq 0) {
        Write-ToLog "No existing DPG Add-In related products detected for cleanup." 'Gray'
        return
    }
    Write-ToLog "Found $($installed.Count) DPG-related product entry(ies). Evaluating for removal (TargetVersion: $TargetVersion)."
    $processed = @{}
    foreach ($app in $installed) {
        $iv = ($app.DisplayVersion -as [string])
        if ($iv) { $iv = $iv.Trim() }
        $guid = $null
        if ($app.UninstallString -match '{[0-9A-Fa-f-]{36}}') { $guid = $Matches[0].ToUpper() }
        if ($guid -and $processed.ContainsKey($guid)) {
            Write-ToLog "Skipping duplicate uninstall entry referencing already processed product $guid ($($app.DisplayName))." 'Gray'
            continue
        }
        if ($iv -and $iv -ne $TargetVersion) {
            Write-ToLog "Removing other installed version: '$($app.DisplayName)' (Version: $iv)" 'Yellow'
            if ($guid) {
                try {
                    $args = "/x $guid /qn /norestart"
                    Write-ToLog "Executing msiexec $args" 'Gray'
                    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru -ErrorAction Stop
                    switch ($proc.ExitCode) {
                        0     { Write-ToLog "Successfully uninstalled $guid (exit 0)." 'Green' }
                        3010  { Write-ToLog "Uninstalled $guid (exit 3010 - reboot required)." 'Yellow' }
                        1605  { Write-ToLog "Product $guid not installed (1605) - benign (likely duplicate entry)." 'Gray' }
                        default { Write-ToLog "Uninstall of $guid returned exit code $($proc.ExitCode)." 'Red' }
                    }
                } catch {
                    Write-ToLog "Failed to uninstall $guid $($_.Exception.Message)" 'Red'
                }
            } else {
                Write-ToLog "Could not parse ProductCode GUID from UninstallString for '$($app.DisplayName)'; skipping removal." 'Yellow'
            }
        } else {
            if ($iv) {
                Write-ToLog "Keeping installed version $iv (matches target) for '$($app.DisplayName)'." 'Green'
            } else {
                Write-ToLog "Entry '$($app.DisplayName)' has no DisplayVersion; skipping removal." 'Gray'
            }
        }
        if ($guid) { $processed[$guid] = $true }
    }
}
#endregion

#region ---------------------------------------------------[Script Execution]------------------------------------------------------

# Configure console output encoding
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
if (!(Test-Path $ReadMeFile)) {
    $ReadMeContent | Out-File -FilePath $ReadMeFile
}

Write-ToLog "Starting installation script for Timengo DPG Add-In" -IsHeader
Write-ToLog "Running as: $env:UserName"

# If $PSScriptRoot is not defined, use current folder
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptRoot = Get-Location
    Write-ToLog "PSScriptRoot was empty, set to current folder: $ScriptRoot"
} else {
    $ScriptRoot = $PSScriptRoot
    Write-ToLog "PSScriptRoot is set to: $ScriptRoot"
}

# Find MSI file(s)
$msiFiles = Get-ChildItem -Path $ScriptRoot -Filter $MsiName -File -ErrorAction SilentlyContinue
if (-not $msiFiles -or $msiFiles.Count -eq 0) {
    Write-ToLog "No $MsiName file found in $ScriptRoot" "Red"
    exit 1
}
if ($msiFiles.Count -gt 1) {
    Write-ToLog "Multiple MSI files detected: $($msiFiles.Name -join ', ')" "Yellow"
    $meta = foreach ($f in $msiFiles) {
        $pv = Get-MsiProductVersion -Path $f.FullName
        $verObj = $null; if ($pv) { try { $verObj = [version]$pv } catch { $verObj = $null } }
        [pscustomobject]@{ File=$f; Name=$f.Name; Raw=$pv; Parsed=$verObj; Time=$f.LastWriteTime }
    }
    foreach ($row in $meta) { Write-ToLog "Candidate MSI: $($row.Name) ProductVersion='$($row.Raw)' Parsed='$($row.Parsed)'" 'Gray' }
    # Prefer one whose ProductVersion matches TargetVersion, else highest version, else newest file
    $chosen = $null
    if ($TargetVersion) {
        $chosen = $meta | Where-Object { $_.Raw -eq $TargetVersion } | Select-Object -First 1
        if ($chosen) { Write-ToLog "Selected MSI because ProductVersion matches TargetVersion ($TargetVersion)." 'Green' }
    }
    if (-not $chosen) {
        $chosen = $meta | Where-Object Parsed | Sort-Object Parsed -Descending | Select-Object -First 1
        if ($chosen) { Write-ToLog "Selected MSI by highest semantic ProductVersion ($($chosen.Raw))." 'Yellow' }
    }
    if (-not $chosen) {
        $chosen = $meta | Sort-Object Time -Descending | Select-Object -First 1
        Write-ToLog "Selected MSI by latest timestamp ($($chosen.File.LastWriteTime))." 'Yellow'
    }
    $msi = $chosen.File
    $msiVersion = $chosen.Raw
    if ($TargetVersion -and -not ($meta.Raw -contains $TargetVersion)) {
        $all = ($meta | ForEach-Object { $_.Raw }) -join ', '
        Write-ToLog "Warning: TargetVersion '$TargetVersion' not found among MSI ProductVersions: $all" 'Yellow'
    }
} else {
    $msi = $msiFiles[0]
    $msiVersion = Get-MsiProductVersion -Path $msi.FullName
    if ($TargetVersion) {
        $tvObj = $null; $msiObj = $null
        try { $tvObj = [version]$TargetVersion } catch {}
        try { $msiObj = [version]$msiVersion } catch {}
        $mismatch = $false
        if ($tvObj -and $msiObj) {
            if ($tvObj -ne $msiObj) { $mismatch = $true }
        } elseif ($msiVersion -ne $TargetVersion) { $mismatch = $true }
        if ($mismatch) { Write-ToLog "Warning: Single MSI ProductVersion '$msiVersion' does not match TargetVersion '$TargetVersion'" 'Yellow' }
    }
}
$msiVersion = ($msiVersion -as [string]).Trim()
Write-ToLog "Discovered deployment MSI: $($msi.Name) (ProductVersion: $msiVersion)"

# Pre-clean: uninstall any other installed versions that differ from target version (script-defined $TargetVersion)
try {
    Uninstall-DpgOtherVersions -TargetVersion $TargetVersion
} catch {
    Write-ToLog "Cleanup of other versions encountered an error: $($_.Exception.Message)" 'Yellow'
}

# Registry import
$regFile = Join-Path -Path $ScriptRoot -ChildPath $RegFileName
if (-not (Test-Path -LiteralPath $regFile)) {
    Write-ToLog "Reg file not found: $regFile" "Red"
    exit 1
}
Write-ToLog "Importing registry settings from: $regFile"
try {
    $regExe = Join-Path $env:windir 'System32\reg.exe'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $regExe = Join-Path $env:windir 'sysnative\reg.exe'
    }
    Start-Process -FilePath $regExe -ArgumentList "import", "`"$regFile`"" -Wait -NoNewWindow -ErrorAction Stop
    Write-ToLog "Reg file '$regFile' imported successfully."
} catch {
    Write-ToLog "Error during reg file import: $($_.Exception.Message)" "Red"
    exit 1
}

# Confirm registry import (use 64-bit view explicitly) with retry (handles slight commit delays)
$maxAttempts = 5
for ($attempt=1; $attempt -le $maxAttempts; $attempt++) {
    if (Test-RegistryValue64 -Path $RegistryPath -Name $RegistryValueName) {
        Write-ToLog "Registry value confirmed in 64-bit hive (attempt $attempt)." 'Green'
        $regConfirmed = $true
        break
    }
    if ($attempt -lt $maxAttempts) {
        Write-ToLog "Registry value '$RegistryValueName' not yet visible (attempt $attempt). Retrying..." 'Yellow'
        Start-Sleep -Milliseconds 600
    }
}
if (-not $regConfirmed) {
    # Fallback: check 32-bit view to provide diagnostic info
    $exists32 = $false
    try {
        $subPath32 = ($RegistryPath -replace '^HKLM:\\','')
        $base32 = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry32)
        $key32 = $base32.OpenSubKey($subPath32)
        if ($key32 -and $null -ne $key32.GetValue($RegistryValueName,$null)) { $exists32 = $true }
    } catch {}
    if ($exists32) {
        Write-ToLog "Registry value found only in 32-bit view (WOW6432Node) but missing in 64-bit hive after $maxAttempts attempts. Failing by policy." 'Red'
    } else {
        Write-ToLog "Registry import failed: value '$RegistryValueName' not found in 64-bit or 32-bit views at $RegistryPath after $maxAttempts attempts." 'Red'
    }
    exit 1
}

# Version enforcement logic
# Determine installed version from uninstall entries (authoritative), fallback to registry value if present.
$installedVersion = $null
$installedProducts = Get-DpgInstalledProducts
if ($installedProducts) {
    # Prefer exact match with target MSI version; else take first (should normally be one after cleanup)
    $match = $installedProducts | Where-Object { $_.DisplayVersion -eq $msiVersion } | Select-Object -First 1
    if (-not $match -and $TargetVersion) {
        $match = $installedProducts | Where-Object { $_.DisplayVersion -eq $TargetVersion } | Select-Object -First 1
    }
    if (-not $match) { $match = $installedProducts | Select-Object -First 1 }
    if ($match) { $installedVersion = ($match.DisplayVersion -as [string]) }
}
if (-not $installedVersion) {
    try { $installedVersion = (Get-ItemProperty -Path $RegistryPath -Name "Version" -ErrorAction SilentlyContinue).Version } catch {}
}
if ($installedVersion) { $installedVersion = $installedVersion.Trim() }
Write-ToLog "Detected installed DPG Add-In version (post-clean): $installedVersion"

$versionsMatch = $false
if ($installedVersion -and $msiVersion) {
    try {
        $verObjInstalled = [version]$installedVersion
        $verObjMsi = [version]$msiVersion
        if ($verObjInstalled -eq $verObjMsi) { $versionsMatch = $true }
    } catch {
        if ($installedVersion -eq $msiVersion) { $versionsMatch = $true }
    }
}

if ($versionsMatch) {
    Write-ToLog "Installed DPG Add-In version ($installedVersion) matches MSI ProductVersion ($msiVersion). Skipping MSI reinstall." "Green"
} else {
    if ($installedVersion -and $msiVersion) {
        Write-ToLog "Version drift detected. Installed: $installedVersion -> Target: $msiVersion (will reinstall)." "Yellow"
    } elseif ($installedVersion -and -not $msiVersion) {
        Write-ToLog "MSI ProductVersion is unknown; cannot compare. Proceeding with reinstall by policy." "Yellow"
    } else {
        Write-ToLog "DPG Add-In not currently installed (no installed product entry matched). Proceeding with initial install." "Yellow"
    }
    try {
        Write-ToLog "Starting MSI installation: $($msi.FullName)"
        $Arguments = "/i `"$($msi.FullName)`" /qn /norestart"
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -PassThru -ErrorAction Stop
        $exitCode = $process.ExitCode
        switch ($exitCode) {
            0     { Write-ToLog "MSI installation completed successfully (exit code 0)"; break }
            3010  { Write-ToLog "MSI installation completed (exit code 3010: restart required). Treating as success." "Yellow"; break }
            default {
                Write-ToLog "Installation failed with exit code: $exitCode" "Red"
                exit $exitCode
            }
        }
    } catch {
        Write-ToLog "Error during MSI installation: $($_.Exception.Message)" "Red"
        exit 1
    }
}

Write-ToLog "Ending installation script for Timengo DPG Add-In" -IsHeader
#endregion