#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$Prefix                   = "AccessibilityAssistant"
[string]$CorpDataPath             = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName       = "#${Prefix}-Detection"
[string]$OldProductNamePattern    = "(?i)Accessibility\s*Assistant"
[bool]$EnableVerboseLogging       = $true
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
    $timeStamp = Get-Date -UFormat "%T"
    $shortDate = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
    if (!(Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
    }
    if ($IsHeader) {
        $Log = "################################################################`n         $shortDate $timeStamp  $LogMsg`n################################################################"
    } else {
        $Log = "$timeStamp - $LogMsg"
    }
    $Log | Write-Host -ForegroundColor $LogColor
    $Log | Out-File -FilePath $LogFile -Append
}

function Write-DebugToLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogMsg)
    if ($EnableVerboseLogging) {
        Write-ToLog "[DEBUG] $LogMsg" 'DarkGray'
    }
}

function Get-RegistryUninstallEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$NamePattern)

    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $results = @()
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($p.DisplayName)) { return }
                if ([regex]::IsMatch("$($p.DisplayName) $($p.Publisher)", $NamePattern)) {
                    $results += [pscustomobject]@{
                        DisplayName = $p.DisplayName
                        ScopePath   = $root
                        Source      = 'Registry'
                    }
                }
            } catch {}
        }
    }
    return @($results)
}

function Get-MsiProductsExEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$NamePattern)

    $results = @()
    $windowsInstaller = $null

    try {
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $products = @($windowsInstaller.ProductsEx('', '', 7))
        Write-DebugToLog "ProductsEx total products: $($products.Count)"

        foreach ($product in $products) {
            try {
                $productName = [string]$product.InstallProperty('ProductName')
                $publisher = [string]$product.InstallProperty('Publisher')
                $installSource = [string]$product.InstallProperty('InstallSource')
                $localPackage = [string]$product.InstallProperty('LocalPackage')
                $productCode = [string]$product.ProductCode

                $searchText = "$productName $publisher $installSource $localPackage $productCode"
                if ([string]::IsNullOrWhiteSpace($searchText)) { continue }
                if ($searchText -notmatch $NamePattern) { continue }

                $results += [pscustomobject]@{
                    DisplayName = $productName
                    ScopePath   = "MSI:$([string]$product.Context)"
                    Source      = 'MSIProductsEx'
                }
            } catch {}
        }
    }
    catch {
        Write-ToLog "MSI ProductsEx query failed: $($_.Exception.Message)" 'Yellow'
    }
    finally {
        if ($windowsInstaller) {
            try { $null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($windowsInstaller) } catch {}
        }
    }

    return @($results)
}

function Get-LoadedUserSids {
    [CmdletBinding()]
    param()

    $sids = @()
    Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | ForEach-Object {
        $sid = $_.PSChildName
        if ($sid -match '^S-1-5-21-\d+-\d+-\d+-\d+$') {
            $sids += $sid
        }
    }

    return @($sids | Select-Object -Unique)
}

function Test-IsSkippableProfilePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfilePath)

    $leaf = Split-Path -Path $ProfilePath -Leaf
    return $leaf -in @('Default', 'Default User', 'defaultuser0', 'Public', 'All Users')
}

function Get-UnloadedUserProfiles {
    [CmdletBinding()]
    param()

    $loadedSids = Get-LoadedUserSids
    $profiles = @()
    $profileListRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

    if (-not (Test-Path $profileListRoot)) {
        return @()
    }

    Get-ChildItem -Path $profileListRoot -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $sid = $_.PSChildName
            if ($sid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { return }
            if ($loadedSids -contains $sid) { return }

            $profile = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
            $profilePath = [Environment]::ExpandEnvironmentVariables([string]$profile.ProfileImagePath)
            if ([string]::IsNullOrWhiteSpace($profilePath)) { return }
            if (Test-IsSkippableProfilePath -ProfilePath $profilePath) {
                Write-DebugToLog "Skipping special profile path: $profilePath"
                return
            }

            $ntUserDat = Join-Path $profilePath 'NTUSER.DAT'
            if (-not (Test-Path -LiteralPath $ntUserDat)) { return }

            $profiles += [pscustomobject]@{
                Sid         = $sid
                ProfilePath = $profilePath
                NtUserDat   = $ntUserDat
            }
        } catch {}
    }

    return @($profiles)
}

function Invoke-RegLoad {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HiveName,
        [Parameter(Mandatory)][string]$HiveFile
    )

    $process = Start-Process -FilePath 'reg.exe' -ArgumentList @('load', "HKU\$HiveName", $HiveFile) -Wait -PassThru -NoNewWindow -ErrorAction Stop
    return $process.ExitCode
}

function Invoke-RegUnload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$HiveName)

    $process = Start-Process -FilePath 'reg.exe' -ArgumentList @('unload', "HKU\$HiveName") -Wait -PassThru -NoNewWindow -ErrorAction Stop
    return $process.ExitCode
}

function Get-OldAddinEntriesFromRoots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Roots,
        [Parameter(Mandatory)][string]$SourceLabel,
        [Parameter(Mandatory)][string]$NamePattern
    )

    $results = @()
    foreach ($root in $Roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                $searchText = "$($_.PSChildName) $($p.FriendlyName) $($p.Description) $($p.Manifest)"
                if ([regex]::IsMatch($searchText, $NamePattern)) {
                    $results += [pscustomobject]@{
                        KeyPath = $_.PSPath
                        Root    = $root
                        Source  = $SourceLabel
                    }
                }
            } catch {}
        }
    }

    return @($results)
}

function Get-OldAddinEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$NamePattern)

    $roots = @(
        'HKLM:\Software\Microsoft\Office\Excel\Addins',
        'HKLM:\Software\Microsoft\Office\Word\Addins',
        'HKLM:\Software\Microsoft\Office\Outlook\Addins',
        'HKLM:\Software\WOW6432Node\Microsoft\Office\Excel\Addins',
        'HKLM:\Software\WOW6432Node\Microsoft\Office\Word\Addins',
        'HKLM:\Software\WOW6432Node\Microsoft\Office\Outlook\Addins'
    )

    $userSids = Get-LoadedUserSids
    foreach ($sid in $userSids) {
        $roots += @(
            "HKU:\$sid\Software\Microsoft\Office\Excel\Addins",
            "HKU:\$sid\Software\Microsoft\Office\Word\Addins",
            "HKU:\$sid\Software\Microsoft\Office\Outlook\Addins"
        )
    }

    $results = @()
    $results += Get-OldAddinEntriesFromRoots -Roots $roots -SourceLabel 'loaded hives' -NamePattern $NamePattern

    $unloadedProfiles = Get-UnloadedUserProfiles
    foreach ($profile in $unloadedProfiles) {
        $tempHiveName = "{0}_{1}" -f $Prefix, ([guid]::NewGuid().ToString('N'))
        $hiveLoaded = $false

        try {
            Write-DebugToLog "Loading user hive for detection, SID $($profile.Sid): $($profile.NtUserDat)"
            $loadExitCode = Invoke-RegLoad -HiveName $tempHiveName -HiveFile $profile.NtUserDat
            if ($loadExitCode -ne 0) {
                Write-ToLog "Failed to load hive for detection, SID $($profile.Sid). reg.exe exit code: $loadExitCode" 'Yellow'
                continue
            }

            $hiveLoaded = $true
            $profileRoots = @(
                "Registry::HKEY_USERS\$tempHiveName\Software\Microsoft\Office\Excel\Addins",
                "Registry::HKEY_USERS\$tempHiveName\Software\Microsoft\Office\Word\Addins",
                "Registry::HKEY_USERS\$tempHiveName\Software\Microsoft\Office\Outlook\Addins"
            )

            $results += Get-OldAddinEntriesFromRoots -Roots $profileRoots -SourceLabel "unloaded profile $($profile.Sid)" -NamePattern $NamePattern
        }
        catch {
            Write-ToLog "Error scanning unloaded profile $($profile.Sid): $($_.Exception.Message)" 'Yellow'
        }
        finally {
            if ($hiveLoaded) {
                $unloadExitCode = Invoke-RegUnload -HiveName $tempHiveName
                if ($unloadExitCode -ne 0) {
                    Write-ToLog "Failed to unload hive after detection for SID $($profile.Sid). reg.exe exit code: $unloadExitCode" 'Yellow'
                }
            }
        }
    }

    return @($results | Select-Object KeyPath, Root, Source -Unique)
}
#endregion

#region ---------------------------------------------------[Detection Logic]-------------------------------------------------------
$null = cmd /c ''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

Write-ToLog "Starting AccessibilityAssistant pre-requisite detection" -IsHeader
Write-ToLog "Running as: $env:USERDOMAIN\$env:USERNAME"

try {
    $products = @()
    $products += @(Get-RegistryUninstallEntries -NamePattern $OldProductNamePattern)
    $products += @(Get-MsiProductsExEntries -NamePattern $OldProductNamePattern)
    $products = @($products | Select-Object DisplayName, ScopePath, Source -Unique)

    $addinEntries = @(Get-OldAddinEntries -NamePattern $OldProductNamePattern)

    Write-ToLog "Old product hits: $($products.Count)" 'Gray'
    Write-ToLog "Old add-in key hits: $($addinEntries.Count)" 'Gray'

    if ($products.Count -gt 0) {
        $products | ForEach-Object {
            Write-ToLog "Still installed: $($_.DisplayName) | Scope: $($_.ScopePath) | Source: $($_.Source)" 'Red'
        }
        Write-ToLog "Ending AccessibilityAssistant pre-requisite detection" -IsHeader
        exit 1
    }

    if ($addinEntries.Count -gt 0) {
        $addinEntries | ForEach-Object {
            Write-ToLog "Old add-in key still present: $($_.KeyPath) | Source: $($_.Source)" 'Red'
        }
        Write-ToLog "Ending AccessibilityAssistant pre-requisite detection" -IsHeader
        exit 1
    }

    Write-ToLog "Pre-requisite detected as compliant: AccessibilityAssistant not found." 'Green'
    Write-ToLog "Ending AccessibilityAssistant pre-requisite detection" -IsHeader
    exit 0
}
catch {
    Write-ToLog "Detection error: $($_.Exception.Message)" 'Red'
    Write-ToLog "Ending AccessibilityAssistant pre-requisite detection" -IsHeader
    exit 1
}
#endregion