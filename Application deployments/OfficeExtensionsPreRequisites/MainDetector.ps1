#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$Prefix                   = "OfficeExtensionsPreRequisites"
[string]$CorpDataPath             = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName       = "#${Prefix}-Detection"
[string]$OldProductNamePattern    = "(?i)OptimentorRibbon"
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

function Get-OptimentorAddinEntries {
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
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                $searchText = "$($_.PSChildName) $($p.FriendlyName) $($p.Description) $($p.Manifest)"
                if ([regex]::IsMatch($searchText, $NamePattern)) {
                    $results += [pscustomobject]@{
                        KeyPath = $_.PSPath
                        Root    = $root
                    }
                }
            } catch {}
        }
    }

    return @($results)
}
#endregion

#region ---------------------------------------------------[Detection Logic]-------------------------------------------------------
$null = cmd /c ''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

Write-ToLog "Starting OfficeExtensions pre-requisite detection" -IsHeader
Write-ToLog "Running as: $env:USERDOMAIN\$env:USERNAME"

try {
    $products = @()
    $products += Get-RegistryUninstallEntries -NamePattern $OldProductNamePattern
    $products += Get-MsiProductsExEntries -NamePattern $OldProductNamePattern
    $products = @($products | Select-Object DisplayName, ScopePath, Source -Unique)

    $addinEntries = Get-OptimentorAddinEntries -NamePattern $OldProductNamePattern

    Write-ToLog "Old product hits: $($products.Count)" 'Gray'
    Write-ToLog "Old add-in key hits: $($addinEntries.Count)" 'Gray'

    if ($products.Count -gt 0) {
        $products | ForEach-Object {
            Write-ToLog "Still installed: $($_.DisplayName) | Scope: $($_.ScopePath) | Source: $($_.Source)" 'Red'
        }
        Write-ToLog "Ending OfficeExtensions pre-requisite detection" -IsHeader
        exit 1
    }

    if ($addinEntries.Count -gt 0) {
        $addinEntries | ForEach-Object {
            Write-ToLog "Old add-in key still present: $($_.KeyPath)" 'Red'
        }
        Write-ToLog "Ending OfficeExtensions pre-requisite detection" -IsHeader
        exit 1
    }

    Write-ToLog "Pre-requisite detected as compliant: OptimentorRibbon not found." 'Green'
    Write-ToLog "Ending OfficeExtensions pre-requisite detection" -IsHeader
    exit 0
}
catch {
    Write-ToLog "Detection error: $($_.Exception.Message)" 'Red'
    Write-ToLog "Ending OfficeExtensions pre-requisite detection" -IsHeader
    exit 1
}
#endregion
