#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$Prefix                   = "AccessibilityAssistant"
[string]$CorpDataPath             = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName       = "#${Prefix}"
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
        @{ Scope = 'Machine64'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' },
        @{ Scope = 'Machine32'; Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' },
        @{ Scope = 'User';      Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' }
    )

    $results = @()
    foreach ($root in $roots) {
        if (-not (Test-Path $root.Path)) { continue }
        Get-ChildItem -Path $root.Path -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                $dn = $p.DisplayName
                if ([string]::IsNullOrWhiteSpace($dn)) { return }
                if ($dn -match $NamePattern) {
                    $keyProductCode = $null
                    if ($_.PSChildName -match '^\{[0-9A-Fa-f\-]{36}\}$') {
                        $keyProductCode = $_.PSChildName
                    }
                    $results += [pscustomobject]@{
                        Scope                = $root.Scope
                        RegistryPath         = $_.PSPath
                        RegistryKeyName      = $_.PSChildName
                        DisplayName          = $dn
                        DisplayVersion       = $p.DisplayVersion
                        Publisher            = $p.Publisher
                        UninstallString      = $p.UninstallString
                        QuietUninstallString = $p.QuietUninstallString
                        WindowsInstaller     = $p.WindowsInstaller
                        ProductCode          = $keyProductCode
                        LocalPackage         = $null
                        Source               = 'Registry'
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
        Write-DebugToLog "ProductsEx inspected total: $($products.Count)"

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
                    Scope                = "MSI:$([string]$product.Context)"
                    RegistryPath         = $null
                    RegistryKeyName      = $null
                    DisplayName          = $productName
                    DisplayVersion       = [string]$product.InstallProperty('VersionString')
                    Publisher            = $publisher
                    UninstallString      = $null
                    QuietUninstallString = $null
                    WindowsInstaller     = 1
                    ProductCode          = $productCode
                    LocalPackage         = $localPackage
                    Source               = 'MSIProductsEx'
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

function Get-InstalledProductEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$NamePattern)

    $results = @()
    $results += Get-RegistryUninstallEntries -NamePattern $NamePattern
    $results += Get-MsiProductsExEntries -NamePattern $NamePattern

    return @($results | Select-Object Scope, RegistryPath, RegistryKeyName, DisplayName, DisplayVersion, Publisher, UninstallString, QuietUninstallString, WindowsInstaller, ProductCode, LocalPackage, Source -Unique)
}

function Get-MsiProductCodeFromText {
    [CmdletBinding()]
    param([Parameter()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '\{[0-9A-Fa-f\-]{36}\}')
    if ($m.Success) { return $m.Value }
    return $null
}

function Get-SilentUninstallInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InstalledEntry,
        [Parameter(Mandatory)][string]$LogFolder
    )

    $quiet = $InstalledEntry.QuietUninstallString
    $uninstall = $InstalledEntry.UninstallString
    $productCode = $InstalledEntry.ProductCode
    $localPackage = $InstalledEntry.LocalPackage

    if (-not [string]::IsNullOrWhiteSpace($quiet)) {
        if (-not $productCode) {
            $productCode = Get-MsiProductCodeFromText -Text $quiet
        }
        return [pscustomobject]@{
            Source       = 'QuietUninstallString'
            FilePath     = 'cmd.exe'
            ArgumentList = "/c $quiet"
        }
    }

    if ($productCode) {
        $msiUninstallLog = Join-Path $LogFolder ("{0}-Uninstall-{1}.log" -f $Prefix, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        return [pscustomobject]@{
            Source       = 'MSI-ProductCode'
            FilePath     = 'msiexec.exe'
            ArgumentList = ('/x {0} /qn /norestart /L*v "{1}"' -f $productCode, $msiUninstallLog)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($localPackage) -and (Test-Path -LiteralPath $localPackage)) {
        $msiUninstallLog = Join-Path $LogFolder ("{0}-Uninstall-{1}.log" -f $Prefix, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        return [pscustomobject]@{
            Source       = 'MSI-LocalPackage'
            FilePath     = 'msiexec.exe'
            ArgumentList = ('/x "{0}" /qn /norestart /L*v "{1}"' -f $localPackage, $msiUninstallLog)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($uninstall)) {
        return [pscustomobject]@{
            Source       = 'UninstallString-Raw'
            FilePath     = 'cmd.exe'
            ArgumentList = "/c $uninstall"
        }
    }

    return $null
}

function Remove-RegistryUninstallEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InstalledEntry
    )

    if ([string]::IsNullOrWhiteSpace($InstalledEntry.RegistryPath)) {
        return $false
    }

    try {
        if (Test-Path -LiteralPath $InstalledEntry.RegistryPath) {
            Remove-Item -Path $InstalledEntry.RegistryPath -Recurse -Force -ErrorAction Stop
            Write-ToLog "Removed orphaned registry entry: $($InstalledEntry.RegistryPath)" 'Yellow'
            return $true
        }
    }
    catch {
        Write-ToLog "Failed to remove orphaned registry entry $($InstalledEntry.RegistryPath): $($_.Exception.Message)" 'Yellow'
    }

    return $false
}

function Invoke-OldProductUninstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InstalledEntry,
        [Parameter(Mandatory)][string]$LogFolder
    )

    $silentInfo = Get-SilentUninstallInfo -InstalledEntry $InstalledEntry -LogFolder $LogFolder
    if (-not $silentInfo) {
        Write-ToLog "No uninstall information available for '$($InstalledEntry.DisplayName)' (may already be absent)." 'Yellow'
        return
    }

    Write-ToLog "Prepared uninstall source: $($silentInfo.Source)" 'Cyan'
    Write-ToLog "Uninstall command: $($silentInfo.FilePath) $($silentInfo.ArgumentList)" 'Gray'

    $process = Start-Process -FilePath $silentInfo.FilePath -ArgumentList $silentInfo.ArgumentList -Wait -PassThru -ErrorAction Stop
    $exitCode = $process.ExitCode

    switch ($exitCode) {
        0     { Write-ToLog "Uninstall completed (0)." 'Green' }
        3010  { Write-ToLog "Uninstall completed (3010 restart required)." 'Yellow' }
        1605  {
            Write-ToLog "Product already absent (1605) - cleaning orphaned registry entry." 'Yellow'
            $null = Remove-RegistryUninstallEntry -InstalledEntry $InstalledEntry
        }
        1614  {
            Write-ToLog "Product already uninstalled (1614) - cleaning orphaned registry entry." 'Yellow'
            $null = Remove-RegistryUninstallEntry -InstalledEntry $InstalledEntry
        }
        default { throw "Uninstall failed with exit code: $exitCode" }
    }
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
                Sid        = $sid
                ProfilePath = $profilePath
                NtUserDat  = $ntUserDat
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

function Remove-OldAddinKeysFromRoots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Roots,
        [Parameter(Mandatory)][string]$SourceLabel
    )

    $removedCount = 0
    foreach ($root in $Roots) {
        if (-not (Test-Path $root)) { continue }

        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $props = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                $searchText = "$($_.PSChildName) $($props.FriendlyName) $($props.Description) $($props.Manifest)"
                if ([regex]::IsMatch($searchText, $OldProductNamePattern)) {
                    Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction Stop
                    Write-ToLog "Removed old add-in key from ${SourceLabel}: $($_.PSPath)" 'Yellow'
                    $removedCount++
                }
            } catch {}
        }
    }

    return $removedCount
}

function Remove-OldAddinRegistryEntries {
    [CmdletBinding()]
    param()

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

    $removedCount = Remove-OldAddinKeysFromRoots -Roots $roots -SourceLabel 'loaded hives'

    $unloadedProfiles = Get-UnloadedUserProfiles
    foreach ($profile in $unloadedProfiles) {
        $tempHiveName = "{0}_{1}" -f $Prefix, ([guid]::NewGuid().ToString('N'))
        $hiveLoaded = $false

        try {
            Write-ToLog "Loading user hive for SID $($profile.Sid): $($profile.NtUserDat)" 'Gray'
            $loadExitCode = Invoke-RegLoad -HiveName $tempHiveName -HiveFile $profile.NtUserDat
            if ($loadExitCode -ne 0) {
                Write-ToLog "Failed to load hive for SID $($profile.Sid). reg.exe exit code: $loadExitCode" 'Yellow'
                continue
            }

            $hiveLoaded = $true
            $profileRoots = @(
                "Registry::HKEY_USERS\$tempHiveName\Software\Microsoft\Office\Excel\Addins",
                "Registry::HKEY_USERS\$tempHiveName\Software\Microsoft\Office\Word\Addins",
                "Registry::HKEY_USERS\$tempHiveName\Software\Microsoft\Office\Outlook\Addins"
            )

            $removedCount += Remove-OldAddinKeysFromRoots -Roots $profileRoots -SourceLabel "unloaded profile $($profile.Sid)"
        }
        catch {
            Write-ToLog "Error processing unloaded profile $($profile.Sid): $($_.Exception.Message)" 'Yellow'
        }
        finally {
            if ($hiveLoaded) {
                $unloadExitCode = Invoke-RegUnload -HiveName $tempHiveName
                if ($unloadExitCode -ne 0) {
                    Write-ToLog "Failed to unload hive for SID $($profile.Sid). reg.exe exit code: $unloadExitCode" 'Yellow'
                }
            }
        }
    }

    Write-ToLog "Old add-in cleanup removed $removedCount key(s)." 'Gray'
}
#endregion

#region ---------------------------------------------------[Script Execution]------------------------------------------------------
$null = cmd /c ''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

Write-ToLog "Starting AccessibilityAssistant pre-requisite removal" -IsHeader
Write-ToLog "Running as: $env:USERDOMAIN\$env:USERNAME"

try {
    $oldProducts = @(Get-InstalledProductEntries -NamePattern $OldProductNamePattern)
    Write-ToLog "Old product discovery hits: $($oldProducts.Count)" 'Gray'

    if ($oldProducts.Count -gt 0) {
        foreach ($oldProduct in $oldProducts) {
            Write-ToLog "Uninstalling old product: $($oldProduct.DisplayName) | Source: $($oldProduct.Source) | Scope: $($oldProduct.Scope)" 'Cyan'
            Invoke-OldProductUninstall -InstalledEntry $oldProduct -LogFolder $logpath
        }
        Start-Sleep -Seconds 5
    }

    Remove-OldAddinRegistryEntries

    $remaining = @(Get-InstalledProductEntries -NamePattern $OldProductNamePattern)
    if ($remaining.Count -gt 0) {
        $remaining | ForEach-Object {
            Write-ToLog "Still present: $($_.DisplayName) | Source: $($_.Source) | Scope: $($_.Scope)" 'Red'
        }
        throw "Pre-requisite failed: AccessibilityAssistant still detected after uninstall attempt."
    }

    Write-ToLog "Pre-requisite success: AccessibilityAssistant is removed." 'Green'
    Write-ToLog "Ending AccessibilityAssistant pre-requisite removal" -IsHeader
    exit 0
}
catch {
    Write-ToLog "Pre-requisite failed: $($_.Exception.Message)" 'Red'
    Write-ToLog "Ending AccessibilityAssistant pre-requisite removal" -IsHeader
    exit 1
}
#endregion