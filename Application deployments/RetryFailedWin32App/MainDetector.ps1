# The helper is intended to run through Intune/Company Portal in System context.
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "RetryFailedWin32App detection must run elevated or as System." -ForegroundColor Red
    exit 1
}

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$Prefix                 = "RetryFailedWin32App"
[string]$TargetAppName          = "SetMeToYourAppName"
[string]$TargetAppId            = "00000000-0000-0000-0000-000000000000"
[string]$CorpDataPath           = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName     = "#${Prefix}"
[string]$MarkerRoot             = "C:\ProgramData\Microsoft\IntuneManagementExtension\RetryState"
#endregion

#region ---------------------------------------------------[Static Variables]------------------------------------------------------
[string]$logpath = "$($CorpDataPath)"
if (-not (Test-Path -Path $logpath)) {
    New-Item -Path $logpath -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path -Path $MarkerRoot)) {
    New-Item -Path $MarkerRoot -ItemType Directory -Force | Out-Null
}
[string]$Script:LogFile = "$($logpath)\$($ApplicationLogName)-Detection.log"
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

function ApplicationDetected {
    exit 0
}

function ApplicationNotDetected {
    exit 1
}
#endregion

#region ---------------------------------------------------[Detection Logic]-------------------------------------------------------
$null = cmd /c ''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

Write-ToLog "Starting detection script for failed Win32 app retry helper" -IsHeader
Write-ToLog "Target app name: $TargetAppName"
Write-ToLog "Target app id: $TargetAppId"

if (Test-Path -Path $MarkerFile) {
    Write-ToLog "Marker file found: $MarkerFile" 'Green'
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationDetected
}

Write-ToLog "Marker file not found. Helper app is not detected yet." 'Yellow'
Write-ToLog "Ending detection script" -IsHeader
ApplicationNotDetected
#endregion
