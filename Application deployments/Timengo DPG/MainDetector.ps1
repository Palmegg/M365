#region ---------------------------------------------------[Script parameters]-----------------------------------------------------
#endregion

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$ExpectedVersion            = "7.34.0.0"
[string]$Prefix                     = "TimengoDPG"
[string]$CorpDataPath               = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName         = "#${Prefix}"
[string]$RegistryPath               = "HKLM:\SOFTWARE\Timengo\DPGAddIn"
[string]$RegistryValueName          = "Version"
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

function ApplicationDetected {
    exit 0
}

function ApplicationNotDetected {
    exit 1
}
#endregion

#region ---------------------------------------------------[Detection Logic]-------------------------------------------------------

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


Write-ToLog "Starting detection script for Timengo DPG Add-In" -IsHeader
Write-ToLog "Running as: $env:UserName"

# Get version from WMI (Win32_Product)
if (-not $detectedVersion) {
    $displayName = "DPGAddin"
    try {
        $product = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*$displayName*" }
        if ($product) {
            $detectedVersion = $product.Version
            Write-ToLog "Detected version from Win32_Product: $detectedVersion" "Cyan"
        }
    } catch {
        Write-ToLog "Failed to get version from Win32_Product: $($_.Exception.Message)" "Yellow"
    }
}

if ($detectedVersion) {
    Write-ToLog "Detected Timengo DPG Add-In version: $detectedVersion" "Cyan"
    if ($detectedVersion -eq $ExpectedVersion) {
        Write-ToLog "Detected version matches ExpectedVersion ($ExpectedVersion)." "Green"
        Write-ToLog "Ending detection script" -IsHeader
        ApplicationDetected
    } else {
        Write-ToLog "Detected version ($detectedVersion) does not match ExpectedVersion ($ExpectedVersion)." "Yellow"
        Write-ToLog "Ending detection script" -IsHeader
        ApplicationNotDetected
    }
} else {
    Write-ToLog "Timengo DPG Add-In not detected (no version found in registry or WMI)." "Red"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationNotDetected
}
#endregion
