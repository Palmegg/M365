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
# Discover the FortiClient MSI in script root. Expect exactly one, but tolerate multiple by choosing highest version.
$msiFiles = Get-ChildItem -Path $ScriptRoot -Filter 'FortiClient*.msi' -File -ErrorAction SilentlyContinue
if (-not $msiFiles -or $msiFiles.Count -eq 0) {
    Write-ToLog "No FortiClient*.msi file found in $ScriptRoot" "Red"
    exit 1
}

if ($msiFiles.Count -gt 1) {
    Write-ToLog "Multiple MSI files detected: $($msiFiles.Name -join ', ')" "Yellow"
    # Reuse lightweight selection: pick by highest ProductVersion else newest file
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
    $Msi = $msiFiles[0]
    $msiVersion = Get-MsiProductVersion -Path $Msi.FullName
}

if (-not $msiVersion) {
    Write-ToLog "MSI ProductVersion could not be read (no fallback to filename allowed by policy)." "Yellow"
}

# Normalize (force to string, trim) but do not attempt regex fallback
$rawMsiVersion = $msiVersion
$msiVersion = ($msiVersion -as [string])
if ($msiVersion) {
    try {
        $trimmed = $msiVersion.Trim()
        if ($trimmed -ne $msiVersion) { Write-ToLog "Normalized MSI version: raw='$msiVersion' -> trimmed='$trimmed'" }
        $msiVersion = $trimmed
    } catch {
        Write-ToLog "Failed trimming MSI version string ('$msiVersion'): $($_.Exception.Message)" 'Yellow'
    }
}
$displayMsiVersion = if ($msiVersion) { $msiVersion } else { 'n/a' }
Write-ToLog "Discovered deployment MSI: $($Msi.Name) (ProductVersion: $displayMsiVersion)"

$installedVersion = $preVersion  # already captured earlier

# Normalized comparison (attempt semantic version compare first, fallback to string)
$versionsMatch = $false
if ($installedVersion -and $msiVersion) {
    $verObjInstalled = $null; $verObjMsi = $null
    try { $verObjInstalled = [version]$installedVersion } catch {}
    try { $verObjMsi       = [version]$msiVersion } catch {}
    if ($verObjInstalled -and $verObjMsi) {
        if ($verObjInstalled -eq $verObjMsi) { $versionsMatch = $true }
    } elseif ($installedVersion -eq $msiVersion) {
        $versionsMatch = $true
    }
}

if ($versionsMatch) {
    Write-ToLog "Installed FortiClient version ($installedVersion) matches MSI ProductVersion ($msiVersion). Skipping MSI reinstall." "Green"
} else {
    if ($installedVersion -and $msiVersion) {
        Write-ToLog "Version drift detected. Installed: $installedVersion -> Target: $msiVersion (will reinstall)." "Yellow"
    } elseif ($installedVersion -and -not $msiVersion) {
        Write-ToLog "MSI ProductVersion is unknown; cannot compare. Proceeding with reinstall by policy." "Yellow"
    } else {
        Write-ToLog "FortiClient not currently installed. Proceeding with initial install." "Yellow"
    }

    try {
        Write-ToLog "Starting MSI installation: $($Msi.FullName)"
        $Arguments = "/i `"$($Msi.FullName)`" /qn /norestart"
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

    if (-not (Test-FortiClientInstallation)) {
        Write-ToLog "Post-install verification failed (FortiClient executable missing)" "Red"
        exit 1
    } else {
        Write-ToLog "FortiClient installation verified successfully." "Green"
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

# ----------------------- 64-bit registry verification -----------------------
$base64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::LocalMachine,
    [Microsoft.Win32.RegistryView]::Registry64
)
$tunnelKeyPath = "SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\$Prefix"
if (-not $base64.OpenSubKey($tunnelKeyPath)) {
    Write-ToLog "Registry check (64-bit) failed: $tunnelKeyPath" -LogColor Red
    Write-ToLog "Ending installation script" -IsHeader
    exit 1
} else {
    Write-ToLog "Registry check (64-bit) succeeded: $tunnelKeyPath"
}

$tunnelKeyNative = "HKLM:\\SOFTWARE\\Fortinet\\FortiClient\\Sslvpn\\Tunnels\\$Prefix"
# Post-import validation of Server value (if Endpoint supplied)
if (-not [string]::IsNullOrWhiteSpace($Endpoint)) {
    try {
        $afterServer = (Get-ItemProperty -Path $tunnelKeyNative -Name Server -ErrorAction Stop).Server
        if ($afterServer -ne $Endpoint) {
            Write-ToLog "Post-import validation FAILED: Server='$afterServer' does not match expected Endpoint='$Endpoint'" "Red"
            Write-ToLog "Ending installation script" -IsHeader
            exit 1
        } else {
            Write-ToLog "Post-import validation succeeded: Server matches Endpoint ($Endpoint)" "Green"
        }
    } catch {
        Write-ToLog "Could not read Server value after import: $($_.Exception.Message)" "Red"
        Write-ToLog "Ending installation script" -IsHeader
        exit 1
    }
}

# Set InstalledVersion in registry for version control
$TunnelRegPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\$Prefix"
try {
    if (-not [string]::IsNullOrWhiteSpace($ExpectedVpnVersion)) {
        try {
            Set-ItemProperty -Path $TunnelRegPath -Name "InstalledVersion" -Value $ExpectedVpnVersion -Type String
            Write-ToLog "Set InstalledVersion to $ExpectedVpnVersion in $TunnelRegPath"
        } catch {
            Write-ToLog "Failed to set InstalledVersion in registry: $($_.Exception.Message)" "Red"
            exit 1
        }
    } else {
        Write-ToLog "ExpectedVpnVersion not provided; InstalledVersion not updated." "Yellow"
    }
} catch {
    Write-ToLog "Failed to set InstalledVersion in registry: $($_.Exception.Message)" "Red"
    exit 1
}

Write-ToLog "Ending installation script" -IsHeader

#endregion