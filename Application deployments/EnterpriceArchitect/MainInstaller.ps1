#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$Prefix                         = "EnterpriseArchitect"
[string]$TargetVersion                  = "16.1.1628.14"
[string]$MsiName                        = "easetupfull_x64.msi"
[string]$CorpDataPath                   = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName             = "#${Prefix}"
[string]$ProductName                    = "Enterprise Architect"
[string]$ExtraFilesFolder               = "EADict"
[string]$ExtraFilesDestination          = "C:\Program Files\Sparx Systems\EA"
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

function Get-MsiProductCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    return Get-MsiProperty -Path $Path -Property 'ProductCode'
}

#region -------------------------[ Helper: Detect & Uninstall Other Installed Versions ]-------------------------------------------
function Get-EaInstalledProducts {
    <#
        Returns uninstall registry entries that appear related to Enterprise Architect.
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
                if ($dn -match '(?i)Enterprise Architect') {
                    $results += [pscustomobject]@{
                        DisplayName     = $dn
                        DisplayVersion  = $p.DisplayVersion
                        UninstallString = $p.UninstallString
                        PSPath          = $_.PSPath
                        Publisher       = $p.Publisher
                    }
                }
            } catch {}
        }
    }
    return $results
}

function Uninstall-EaOtherVersions {
    <#
        Uninstalls any detected Enterprise Architect product whose DisplayVersion differs from target version.
        Falls back to parsing ProductCode GUID from UninstallString. Accepts exit codes 0, 3010, 1605 as success.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetVersion
    )
    if ([string]::IsNullOrWhiteSpace($TargetVersion)) {
        Write-ToLog "TargetVersion not supplied to Uninstall-EaOtherVersions; skipping cleanup." 'Yellow'
        return
    }
    $installed = Get-EaInstalledProducts
    if (-not $installed -or $installed.Count -eq 0) {
        Write-ToLog "No existing Enterprise Architect related products detected for cleanup." 'Gray'
        return
    }
    Write-ToLog "Found $($installed.Count) Enterprise Architect related product entry(ies). Evaluating for removal (TargetVersion: $TargetVersion)."
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
                    $logFile = "$logpath\EA-MSI-$iv-Uninstall.log"
                    $args = "/x $guid /L* `"$logFile`" /qn /norestart"
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

Write-ToLog "Starting installation script for Enterprise Architect" -IsHeader
Write-ToLog "Running as: $env:UserName"

# If $PSScriptRoot is not defined, use current folder
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptRoot = Get-Location
    Write-ToLog "PSScriptRoot was empty, set to current folder: $ScriptRoot"
} else {
    $ScriptRoot = $PSScriptRoot
    Write-ToLog "PSScriptRoot is set to: $ScriptRoot"
}

# Find MSI file
$msiPath = Join-Path -Path $ScriptRoot -ChildPath $MsiName
if (-not (Test-Path -LiteralPath $msiPath)) {
    Write-ToLog "MSI file not found: $msiPath" "Red"
    exit 1
}
Write-ToLog "Found MSI file: $msiPath"

# Get MSI properties
$msiVersion = Get-MsiProductVersion -Path $msiPath
$msiProductCode = Get-MsiProductCode -Path $msiPath
if ($msiVersion) { 
    $msiVersion = $msiVersion.Trim() 
    Write-ToLog "MSI ProductVersion: $msiVersion"
} else {
    Write-ToLog "Warning: Could not read ProductVersion from MSI" "Yellow"
}
if ($msiProductCode) {
    Write-ToLog "MSI ProductCode: $msiProductCode"
}

# Validate MSI version against target
if ($msiVersion -and $TargetVersion) {
    if ($msiVersion -ne $TargetVersion) {
        Write-ToLog "Warning: MSI ProductVersion '$msiVersion' does not match TargetVersion '$TargetVersion'" 'Yellow'
    } else {
        Write-ToLog "MSI version matches TargetVersion." 'Green'
    }
}

# Pre-clean: uninstall any other installed versions that differ from target version
try {
    Uninstall-EaOtherVersions -TargetVersion $TargetVersion
} catch {
    Write-ToLog "Cleanup of other versions encountered an error: $($_.Exception.Message)" 'Yellow'
}

# Version enforcement logic
$installedVersion = $null
$installedProducts = Get-EaInstalledProducts
if ($installedProducts) {
    # Prefer exact match with target MSI version; else take first (should normally be one after cleanup)
    $match = $installedProducts | Where-Object { $_.DisplayVersion -eq $msiVersion } | Select-Object -First 1
    if (-not $match -and $TargetVersion) {
        $match = $installedProducts | Where-Object { $_.DisplayVersion -eq $TargetVersion } | Select-Object -First 1
    }
    if (-not $match) { $match = $installedProducts | Select-Object -First 1 }
    if ($match) { $installedVersion = ($match.DisplayVersion -as [string]) }
}
if ($installedVersion) { $installedVersion = $installedVersion.Trim() }
Write-ToLog "Detected installed Enterprise Architect version (post-clean): $installedVersion"

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
    Write-ToLog "Installed Enterprise Architect version ($installedVersion) matches MSI ProductVersion ($msiVersion). Skipping MSI reinstall." "Green"
} else {
    if ($installedVersion -and $msiVersion) {
        Write-ToLog "Version drift detected. Installed: $installedVersion -> Target: $msiVersion (will reinstall)." "Yellow"
    } elseif ($installedVersion -and -not $msiVersion) {
        Write-ToLog "MSI ProductVersion is unknown; cannot compare. Proceeding with reinstall by policy." "Yellow"
    } else {
        Write-ToLog "Enterprise Architect not currently installed (no installed product entry matched). Proceeding with initial install." "Yellow"
    }
    try {
        Write-ToLog "Starting MSI installation: $msiPath"
        $installLogFile = "$logpath\EA-MSI-$TargetVersion-Install.log"
        $Arguments = "/i `"$msiPath`" /L* `"$installLogFile`" ALLUSERS=2 /qn /norestart"
        Write-ToLog "Executing: msiexec.exe $Arguments" 'Gray'
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

# Copy additional files if folder exists
$extraFilesPath = Join-Path -Path $ScriptRoot -ChildPath $ExtraFilesFolder
if (Test-Path -LiteralPath $extraFilesPath -PathType Container) {
    Write-ToLog "Found extra files folder: $ExtraFilesFolder"
    if (-not (Test-Path -LiteralPath $ExtraFilesDestination)) {
        Write-ToLog "Destination folder does not exist: $ExtraFilesDestination" "Yellow"
        Write-ToLog "Creating destination folder: $ExtraFilesDestination"
        try {
            New-Item -Path $ExtraFilesDestination -ItemType Directory -Force | Out-Null
            Write-ToLog "Created destination folder successfully." "Green"
        } catch {
            Write-ToLog "Failed to create destination folder: $($_.Exception.Message)" "Red"
            exit 1
        }
    }
    try {
        Write-ToLog "Copying files from '$ExtraFilesFolder' to '$ExtraFilesDestination'"
        $sourcePattern = Join-Path -Path $extraFilesPath -ChildPath "*.*"
        Copy-Item -Path $sourcePattern -Destination $ExtraFilesDestination -Force -Recurse -ErrorAction Stop
        Write-ToLog "Extra files copied successfully." "Green"
    } catch {
        Write-ToLog "Error copying extra files: $($_.Exception.Message)" "Red"
        exit 1
    }
} else {
    Write-ToLog "No extra files folder found ($ExtraFilesFolder). Skipping file copy." "Gray"
}

Write-ToLog "Ending installation script for Enterprise Architect" -IsHeader
#endregion
