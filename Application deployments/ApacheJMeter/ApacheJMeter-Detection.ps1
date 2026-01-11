#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$ExpectedVersion        = "5.6.3"  # Set to "" to skip version check, or specify exact version (e.g., "5.6.3")
[string]$CorpDataPath           = "$env:LOCALAPPDATA\IntuneManagementLogs"
[string]$ApplicationLogName     = "#ApacheJMeter_Detection"
#endregion

#region ---------------------------------------------------[Static Variables]------------------------------------------------------
[string]$logpath = "$($CorpDataPath)"
if (!(Test-Path -Path $logpath)) {
    New-Item -Path $logpath -ItemType Directory -Force | Out-Null
}
[string]$Script:LogFile = "$($logpath)\$($ApplicationLogName).log"
[string]$DesktopPath = [Environment]::GetFolderPath("Desktop")
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
        $Log = "################################################################`n         $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) $(Get-Date -UFormat "%T") -> $LogMsg`n################################################################"
    }
    else {
        $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    }

    #Echo log
    $Log | Write-host -ForegroundColor $LogColor

    #Write log to file
    $Log | Out-File -FilePath $LogFile -Append
}

function ApplicationDetected {
    Write-ToLog "-> Apache JMeter detected successfully" "Green"
    Write-ToLog "Ending detection script" -IsHeader
    exit 0
}

function ApplicationNotDetected {
    Write-ToLog "-> Apache JMeter not detected" "Red"
    Write-ToLog "Ending detection script" -IsHeader
    exit 1
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

Write-ToLog "Starting Apache JMeter detection script" -IsHeader
Write-ToLog "-> Running as: $env:UserName"
Write-ToLog "-> Looking for folder matching: apache-jmeter-* on desktop"

# Check if Apache JMeter folder exists on desktop (wildcard match)
$JMeterFolders = Get-ChildItem -Path $DesktopPath -Directory -Filter "apache-jmeter-*" -ErrorAction SilentlyContinue

if ($JMeterFolders.Count -eq 0) {
    Write-ToLog "-> ERROR: No Apache JMeter folder found on desktop" "Red"
    ApplicationNotDetected
}

# Use the first matching folder
$TargetPath = $JMeterFolders[0].FullName

Write-ToLog "-> Apache JMeter folder found: $($JMeterFolders[0].Name)" "Green"
Write-ToLog "-> Full path: $TargetPath" "Cyan"

# Extract version from folder name (e.g., apache-jmeter-5.6.3 → 5.6.3)
$FolderName = $JMeterFolders[0].Name
if ($FolderName -match "apache-jmeter-(.+)") {
    $InstalledVersion = $matches[1].Trim()
    Write-ToLog "-> Detected version from folder name: $InstalledVersion" "Cyan"
    
    # If expected version is specified, validate it
    if ($ExpectedVersion -ne "" -and $ExpectedVersion -ne "Unknown") {
        Write-ToLog "-> Expected version: $ExpectedVersion" "Cyan"
        if ($InstalledVersion -eq $ExpectedVersion) {
            Write-ToLog "-> Version match: $InstalledVersion = $ExpectedVersion" "Green"
        }
        else {
            Write-ToLog "-> Version mismatch: $InstalledVersion != $ExpectedVersion" "Red"
            Write-ToLog "-> Required version $ExpectedVersion not found" "Red"
            ApplicationNotDetected
        }
    }
}
else {
    Write-ToLog "-> Warning: Could not extract version from folder name" "Yellow"
    # If version is required but can't be extracted, fail the detection
    if ($ExpectedVersion -ne "" -and $ExpectedVersion -ne "Unknown") {
        Write-ToLog "-> ERROR: Version requirement specified but cannot verify version from folder name" "Red"
        ApplicationNotDetected
    }
}

# If no version check required or version file doesn't exist, just verify folder exists with content
$FileCount = (Get-ChildItem -Path $TargetPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
Write-ToLog "-> Found $FileCount files in Apache JMeter folder" "Cyan"

if ($FileCount -eq 0) {
    Write-ToLog "-> ERROR: Apache JMeter folder is empty" "Red"
    ApplicationNotDetected
}

# Additional verification checks
Write-ToLog "-> Performing additional verification checks..." "Cyan"

# Check for critical JMeter files
$CriticalFiles = @(
    "bin\jmeter.bat",
    "bin\ApacheJMeter.jar",
    "lib\jorphan.jar"
)

$MissingFiles = @()
foreach ($CriticalFile in $CriticalFiles) {
    $FilePath = Join-Path -Path $TargetPath -ChildPath $CriticalFile
    if (!(Test-Path -Path $FilePath)) {
        $MissingFiles += $CriticalFile
        Write-ToLog "-> Missing critical file: $CriticalFile" "Yellow"
    }
    else {
        Write-ToLog "-> Found: $CriticalFile" "Green"
    }
}

if ($MissingFiles.Count -gt 0) {
    Write-ToLog "-> ERROR: $($MissingFiles.Count) critical file(s) missing" "Red"
    ApplicationNotDetected
}

Write-ToLog "-> All verification checks passed" "Green"
ApplicationDetected

#endregion
