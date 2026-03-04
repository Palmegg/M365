#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$Prefix                         = "GetOrganized"
[string]$TargetVersion                  = "6.33.0712"
[string]$VersionFolder                  = "6.33.0712"
[string]$MsiName                        = "setup.msi"
[string]$CorpDataPath                   = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName             = "#${Prefix}"
[string]$ProductName                    = "GetOrganized"
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
    if (-not (Test-Path -LiteralPath $Path)) { 
        return $null 
    }
    
    $windowsInstaller = $null
    $database = $null
    $view = $null
    $result = $null
    
    try {
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $database = $windowsInstaller.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $windowsInstaller, @($Path, 0))
        $query = "SELECT Value FROM Property WHERE Property='$Property'"
        $view = $database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $database, ($query))
        $null = $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
        
        $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
        if ($record) {
            $value = $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, 1)
            if ($value) {
                # Convert to string and aggressively clean
                $valueStr = [string]$value
                # Remove ALL whitespace characters from beginning and end
                $valueStr = $valueStr.TrimStart([char[]]@(32,9,10,13,160,8232,8233))
                $valueStr = $valueStr.TrimEnd([char[]]@(32,9,10,13,160,8232,8233))
                $valueStr = $valueStr -replace '^\s+', '' -replace '\s+$', ''
                
                if (-not [string]::IsNullOrWhiteSpace($valueStr)) {
                    $result = $valueStr
                }
            }
        }
    }
    catch {
        # Silently fail
    }
    finally {
        if ($view) { 
            try { $null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($view) } catch {}
        }
        if ($database) { 
            try { $null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($database) } catch {}
        }
        if ($windowsInstaller) { 
            try { $null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($windowsInstaller) } catch {}
        }
    }
    
    return $result
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

#region -------------------------[ Helper: Detect Installed Versions ]-------------------------------------------
function Get-GetOrganizedInstalledProducts {
    <#
        Returns uninstall registry entries that appear related to GetOrganized.
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
                if ($dn -match '(?i)GetOrganized') {
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

Write-ToLog "Starting installation script for GetOrganized" -IsHeader
Write-ToLog "Running as: $env:UserName"

# If $PSScriptRoot is not defined, use current folder
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptRoot = Get-Location
    Write-ToLog "PSScriptRoot was empty, set to current folder: $ScriptRoot"
} else {
    $ScriptRoot = $PSScriptRoot
    Write-ToLog "PSScriptRoot is set to: $ScriptRoot"
}

# Find MSI file in version folder
$versionFolderPath = Join-Path -Path $ScriptRoot -ChildPath $VersionFolder
if (-not (Test-Path -LiteralPath $versionFolderPath -PathType Container)) {
    Write-ToLog "Version folder not found: $versionFolderPath" "Red"
    exit 1
}
Write-ToLog "Found version folder: $versionFolderPath"

$msiPath = Join-Path -Path $versionFolderPath -ChildPath $MsiName
if (-not (Test-Path -LiteralPath $msiPath)) {
    Write-ToLog "MSI file not found: $msiPath" "Red"
    exit 1
}
Write-ToLog "Found MSI file: $msiPath"

# Get MSI properties
$msiVersion = Get-MsiProductVersion -Path $msiPath
$msiProductCode = Get-MsiProductCode -Path $msiPath

Write-ToLog "DEBUG: Raw msiVersion type: $($msiVersion.GetType().FullName)" 'Magenta'
Write-ToLog "DEBUG: Raw msiVersion length: $($msiVersion.Length)" 'Magenta'
Write-ToLog "DEBUG: Raw msiVersion value: [$msiVersion]" 'Magenta'

if (-not [string]::IsNullOrWhiteSpace($msiVersion)) {
    Write-ToLog "MSI ProductVersion: [$msiVersion]"
} else {
    Write-ToLog "Warning: Could not read ProductVersion from MSI" "Yellow"
}

if (-not [string]::IsNullOrWhiteSpace($msiProductCode)) {
    Write-ToLog "MSI ProductCode: $msiProductCode"
}

# Check currently installed version
$installedVersion = $null
$installedProducts = Get-GetOrganizedInstalledProducts
if ($installedProducts) {
    $match = $installedProducts | Select-Object -First 1
    if ($match -and $match.DisplayVersion) {
        $installedVersion = $match.DisplayVersion.Trim()
        Write-ToLog "Currently installed: $($match.DisplayName) - Version: [$installedVersion]" "Cyan"
    }
}

# Determine if we should install/upgrade
$shouldInstall = $true
if ($installedVersion -and $msiVersion) {
    # Debug comparison
    Write-ToLog "DEBUG: Comparing versions..." 'Magenta'
    Write-ToLog "DEBUG: installedVersion = [$installedVersion] (length: $($installedVersion.Length))" 'Magenta'
    Write-ToLog "DEBUG: msiVersion = [$msiVersion] (length: $($msiVersion.Length))" 'Magenta'
    Write-ToLog "DEBUG: Are they equal? $($installedVersion -eq $msiVersion)" 'Magenta'
    
    if ($installedVersion -eq $msiVersion) {
        Write-ToLog "Installed version matches MSI version. Skipping installation." "Green"
        $shouldInstall = $false
    } else {
        Write-ToLog "Version difference detected. Will upgrade from [$installedVersion] to [$msiVersion]." "Yellow"
    }
} elseif ($installedVersion) {
    Write-ToLog "Cannot determine MSI version. Will attempt installation anyway." "Yellow"
} else {
    Write-ToLog "GetOrganized not currently installed. Proceeding with fresh installation." "Cyan"
}

if ($shouldInstall) {
    try {
        Write-ToLog "Starting MSI installation/upgrade: $msiPath"
        $installLogFile = "$logpath\GetOrganized-MSI-Install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        $Arguments = "/i `"$msiPath`" /L*v `"$installLogFile`" ALLUSERS=2 /qn /norestart"
        Write-ToLog "Executing: msiexec.exe $Arguments" 'Gray'
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -PassThru -ErrorAction Stop
        $exitCode = $process.ExitCode
        switch ($exitCode) {
            0     { Write-ToLog "Installation completed successfully (exit code 0)" "Green"; break }
            3010  { Write-ToLog "Installation completed successfully (exit code 3010: restart required)" "Yellow"; break }
            1638  { Write-ToLog "Another version is already installed (exit code 1638). This is acceptable." "Yellow"; break }
            default {
                Write-ToLog "Installation failed with exit code: $exitCode. Check log: $installLogFile" "Red"
                exit $exitCode
            }
        }
    } catch {
        Write-ToLog "Error during MSI installation: $($_.Exception.Message)" "Red"
        exit 1
    }
}

Write-ToLog "Ending installation script for GetOrganized" -IsHeader
#endregion