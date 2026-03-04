#region ---------------------------------------------------[Script parameters]-----------------------------------------------------
#endregion

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$ExpectedVersion            = "17.1.1716"
[string]$Prefix                     = "EnterpriseArchitect"
[string]$CorpDataPath               = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName         = "#${Prefix}"
[string]$ProductName                = "Enterprise Architect"
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

Write-ToLog "Starting detection script for Enterprise Architect" -IsHeader
Write-ToLog "Running as: $env:UserName"

# Function to get version from registry uninstall keys
function Get-InstalledVersion {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                $dn = $p.DisplayName
                if ([string]::IsNullOrWhiteSpace($dn)) { return }
                if ($dn -match '(?i)Enterprise Architect') {
                    return [pscustomobject]@{
                        DisplayName     = $dn
                        DisplayVersion  = $p.DisplayVersion
                        Publisher       = $p.Publisher
                    }
                }
            } catch {}
        }
    }
}

$detectedVersion = $null

# Check registry for installed version
$installedProduct = Get-InstalledVersion | Select-Object -First 1
if ($installedProduct) {
    $detectedVersion = $installedProduct.DisplayVersion
    if ($detectedVersion) { 
        $detectedVersion = $detectedVersion.Trim() 
    }
    Write-ToLog "Detected version from registry: $detectedVersion (Product: $($installedProduct.DisplayName))" "Cyan"
}

if ($detectedVersion) {
    Write-ToLog "Detected Enterprise Architect version: $detectedVersion" "Cyan"
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
    Write-ToLog "Enterprise Architect not detected (no version found in registry)." "Red"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationNotDetected
}
#endregion
