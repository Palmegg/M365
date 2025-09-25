#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$Prefix                         = "TimengoDPG"
[string]$ExpectedVersion                = "7.34.0.0"
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
        [pscustomobject]@{ File=$f; Raw=$pv; Parsed=$verObj; Time=$f.LastWriteTime }
    }
    $chosen = $meta | Where-Object Parsed | Sort-Object Parsed -Descending | Select-Object -First 1
    if (-not $chosen) { $chosen = $meta | Sort-Object Time -Descending | Select-Object -First 1 }
    $msi = $chosen.File
    $msiVersion = $chosen.Raw
} else {
    $msi = $msiFiles[0]
    $msiVersion = Get-MsiProductVersion -Path $msi.FullName
}
$msiVersion = ($msiVersion -as [string]).Trim()
Write-ToLog "Discovered deployment MSI: $($msi.Name) (ProductVersion: $msiVersion)"

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

# Confirm registry import
Start-Sleep -Seconds 2
Write-ToLog "Checking registry path: $RegistryPath for value: $RegistryValueName"
if (!(Get-ItemProperty -Path $RegistryPath -Name $RegistryValueName -ErrorAction SilentlyContinue)) {
    Write-ToLog "Registry import failed. '$RegistryValueName' not found in '$RegistryPath'." "Red"
    exit 1
} else {
    Write-ToLog "Registry key confirmed successfully." "Green"
}

# Version enforcement logic
$installedVersion = $null
try {
    $installedVersion = (Get-ItemProperty -Path $RegistryPath -Name "Version" -ErrorAction SilentlyContinue).Version
} catch {}
if ($installedVersion) { $installedVersion = $installedVersion.Trim() }
Write-ToLog "Detected installed DPG Add-In version: $installedVersion"

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
        Write-ToLog "DPG Add-In not currently installed. Proceeding with initial install." "Yellow"
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