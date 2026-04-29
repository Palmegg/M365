# The helper must run as System or an elevated administrator because it edits HKLM
# and restarts the IntuneManagementExtension service.
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "RetryFailedWin32App must run elevated or as System." -ForegroundColor Red
    exit 1
}

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$Prefix                         = "RetryFailedWin32App"
[string]$TargetAppName                  = "SetMeToYourAppName"
[string]$TargetAppId                    = "00000000-0000-0000-0000-000000000000"
[string]$CorpDataPath                   = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName             = "#${Prefix}"
[string]$IntuneLogsPath                 = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$IntuneWin32AppsRegistryPath    = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps"
[string]$MarkerRoot                     = "C:\ProgramData\Microsoft\IntuneManagementExtension\RetryState"
#endregion

#region ---------------------------------------------------[Static Variables]------------------------------------------------------
[string]$logpath = "$($CorpDataPath)"
if (-not (Test-Path -Path $logpath)) {
    New-Item -Path $logpath -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path -Path $MarkerRoot)) {
    New-Item -Path $MarkerRoot -ItemType Directory -Force | Out-Null
}
[string]$Script:LogFile = "$($logpath)\$($ApplicationLogName).log"
[string]$Script:MarkerFile = Join-Path -Path $MarkerRoot -ChildPath "$($TargetAppId).json"
#endregion

#region ---------------------------------------------------[Functions]-------------------------------------------------------------
function Write-ToLog {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $LogMsg,
        [Parameter()] [string] $LogColor = "White",
        [Parameter()] [switch] $IsHeader = $false
    )

    if (-not (Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
    }

    if ($IsHeader) {
        $Log = "################################################################`n         $(Get-Date -Format (Get-Culture).DateTimeFormat.ShortDatePattern) $(Get-Date -UFormat "%T")  $LogMsg`n################################################################"
    } else {
        $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    }

    $Log | Write-Host -ForegroundColor $LogColor
    $Log | Out-File -FilePath $LogFile -Append
}

function Test-ValidGuid {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GuidText)

    return [bool]([guid]::TryParse($GuidText, [ref]([guid]::Empty)))
}

function Get-Win32AppRegistrySubKeys {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -Path $IntuneWin32AppsRegistryPath)) {
        return @()
    }

    $excludedNames = @('OperationalState', 'Reporting')
    return @(Get-ChildItem -Path $IntuneWin32AppsRegistryPath -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $pathSegments = $_.Name -split '\\'
            -not ($pathSegments | Where-Object { $_ -in $excludedNames })
        })
}

function Get-TargetAppStateKeys {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AppId)

    $escapedAppId = [regex]::Escape($AppId)
    $targetPattern = "^{0}(_\d+)?$" -f $escapedAppId
    $results = @()

    foreach ($registryKey in (Get-Win32AppRegistrySubKeys)) {
        if ($registryKey.PSChildName -eq 'GRS') { continue }
        if ($registryKey.PSChildName -match $targetPattern) {
            $results += [pscustomobject]@{
                ParentPath   = Split-Path -Path $registryKey.Name -Parent
                KeyName      = $registryKey.PSChildName
                RegistryPath = $registryKey.PSPath
            }
        }
    }

    return @($results)
}

function Get-TargetHashesFromLogs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AppId)

    if (-not (Test-Path -Path $IntuneLogsPath)) {
        return @()
    }

    $logFiles = @(
        Get-ChildItem -Path $IntuneLogsPath -Filter 'IntuneManagementExtension*.log' -File -ErrorAction SilentlyContinue
        Get-ChildItem -Path $IntuneLogsPath -Filter 'AppWorkload*.log' -File -ErrorAction SilentlyContinue
    ) | Sort-Object LastWriteTime -Descending -Unique

    $escapedAppId = [regex]::Escape($AppId)
    $appLinePattern = "\[Win32App\]\[GRSManager\] App with id: {0}(_\d+)? is (not )?expired\." -f $escapedAppId
    $hashes = New-Object 'System.Collections.Generic.List[string]'

    foreach ($logFile in $logFiles) {
        $lines = Get-Content -Path $logFile.FullName -ErrorAction SilentlyContinue
        if (-not $lines) { continue }

        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -notmatch $appLinePattern) { continue }

            $hashFound = $false
            $maxForwardIndex = [Math]::Min($i + 5, $lines.Count - 1)
            for ($j = $i + 1; $j -le $maxForwardIndex; $j++) {
                if ($lines[$j] -match 'Hash\s*=\s*(?<Hash>.+?)\s*$') {
                    $hash = $Matches['Hash'].Trim()
                    if (-not [string]::IsNullOrWhiteSpace($hash)) {
                        $hashes.Add($hash)
                        $hashFound = $true
                        break
                    }
                }
            }

            if ($hashFound) { continue }

            $minBackwardIndex = [Math]::Max($i - 5, 0)
            for ($k = $minBackwardIndex; $k -le $maxForwardIndex; $k++) {
                if ($lines[$k] -match 'storage path:\s*.+\\GRS\\(?<Hash>[^\\]+)\\\.') {
                    $hash = $Matches['Hash'].Trim()
                    if (-not [string]::IsNullOrWhiteSpace($hash)) {
                        $hashes.Add($hash)
                        break
                    }
                }
            }
        }
    }

    return [string[]]@($hashes | Select-Object -Unique)
}

function Get-TargetGrsKeys {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyCollection()][string[]]$Hashes)

    if (-not $Hashes -or $Hashes.Count -eq 0) {
        return @()
    }

    $hashSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($hash in $Hashes) {
        [void]$hashSet.Add($hash)
    }

    $results = @()
    $grsContainerKeys = @(Get-Win32AppRegistrySubKeys | Where-Object { $_.PSChildName -eq 'GRS' })
    foreach ($grsContainerKey in $grsContainerKeys) {
        Get-ChildItem -Path $grsContainerKey.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
            if ($hashSet.Contains($_.PSChildName)) {
                $results += [pscustomobject]@{
                    ParentPath   = $grsContainerKey.Name
                    Hash         = $_.PSChildName
                    RegistryPath = $_.PSPath
                }
            }
        }
    }

    return @($results)
}

function Remove-RegistryObjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RegistryObjects,
        [Parameter(Mandatory)][string]$ObjectTypeName
    )

    $removedCount = 0

    foreach ($registryObject in $RegistryObjects) {
        Remove-Item -Path $registryObject.RegistryPath -Recurse -Force -ErrorAction Stop
        Write-ToLog "Removed ${ObjectTypeName}: $($registryObject.RegistryPath)" 'Yellow'
        $removedCount++
    }

    return $removedCount
}

function Write-RegistryMatchesToLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RegistryObjects,
        [Parameter(Mandatory)][string]$ObjectTypeName
    )

    if (-not $RegistryObjects -or $RegistryObjects.Count -eq 0) {
        Write-ToLog "No ${ObjectTypeName} matches found." 'Gray'
        return
    }

    foreach ($registryObject in $RegistryObjects) {
        Write-ToLog "Matched ${ObjectTypeName}: $($registryObject.RegistryPath)" 'Cyan'
    }
}

function Save-RunMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][int]$RemovedStateKeys,
        [Parameter(Mandatory)][int]$RemovedGrsKeys
    )

    $markerContent = [pscustomobject]@{
        TargetAppId      = $AppId
        TargetAppName    = $AppName
        LastRunUtc       = (Get-Date).ToUniversalTime().ToString('o')
        RemovedStateKeys = $RemovedStateKeys
        RemovedGrsKeys   = $RemovedGrsKeys
        ComputerName     = $env:COMPUTERNAME
    }

    $markerContent | ConvertTo-Json | Out-File -FilePath $MarkerFile -Encoding utf8 -Force
    Write-ToLog "Updated detection marker: $MarkerFile" 'Gray'
}
#endregion

#region ---------------------------------------------------[Script Execution]------------------------------------------------------
$null = cmd /c ''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

Write-ToLog "Starting failed Win32 app retry helper" -IsHeader
Write-ToLog "Running as: ${env:USERDOMAIN}\$env:USERNAME"
Write-ToLog "Target app name: $TargetAppName"
Write-ToLog "Target app id: $TargetAppId"

try {
    if (-not (Test-ValidGuid -GuidText $TargetAppId)) {
        throw "TargetAppId is not a valid GUID. Update the script before packaging it."
    }

    if (-not (Test-Path -Path $IntuneWin32AppsRegistryPath)) {
        throw "Intune Win32 app registry path not found: $IntuneWin32AppsRegistryPath"
    }

    $targetAppStateKeys = @(Get-TargetAppStateKeys -AppId $TargetAppId)
    Write-ToLog "Matched Win32 app state key(s): $($targetAppStateKeys.Count)" 'Gray'
    Write-RegistryMatchesToLog -RegistryObjects $targetAppStateKeys -ObjectTypeName 'Win32 app state key'

    $targetHashes = @(Get-TargetHashesFromLogs -AppId $TargetAppId)
    if ($targetHashes.Count -gt 0) {
        Write-ToLog "Matched GRS hash(es): $($targetHashes -join ', ')" 'Gray'
    } else {
        Write-ToLog "No matching GRS hash found in Intune logs. The Win32 app state key will still be removed if present." 'Yellow'
    }

    $targetGrsKeys = @()
    if ($targetHashes.Count -gt 0) {
        $targetGrsKeys = @(Get-TargetGrsKeys -Hashes $targetHashes)
    }
    Write-ToLog "Matched GRS key(s): $($targetGrsKeys.Count)" 'Gray'
    Write-RegistryMatchesToLog -RegistryObjects $targetGrsKeys -ObjectTypeName 'GRS key'

    if ($targetAppStateKeys.Count -eq 0 -and $targetGrsKeys.Count -eq 0) {
        throw "No matching Win32 app state key or GRS key was found for app id $TargetAppId."
    }

    $removedStateKeys = 0
    $removedGrsKeys = 0

    if ($targetAppStateKeys.Count -gt 0) {
        $removedStateKeys = Remove-RegistryObjects -RegistryObjects $targetAppStateKeys -ObjectTypeName 'Win32 app state key'
    }

    if ($targetGrsKeys.Count -gt 0) {
        $removedGrsKeys = Remove-RegistryObjects -RegistryObjects $targetGrsKeys -ObjectTypeName 'GRS key'
    }

    Write-ToLog "Restarting IntuneManagementExtension service to force reevaluation." 'Cyan'
    Restart-Service -Name 'IntuneManagementExtension' -Force -ErrorAction Stop

    Save-RunMarker -AppId $TargetAppId -AppName $TargetAppName -RemovedStateKeys $removedStateKeys -RemovedGrsKeys $removedGrsKeys

    Write-ToLog "Retry helper completed successfully. Removed state keys: $removedStateKeys | Removed GRS keys: $removedGrsKeys" 'Green'
    Write-ToLog "Ending failed Win32 app retry helper" -IsHeader
    exit 0
}
catch {
    Write-ToLog "Retry helper failed: $($_.Exception.Message)" 'Red'
    Write-ToLog "Ending failed Win32 app retry helper" -IsHeader
    exit 1
}
#endregion
