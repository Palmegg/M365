#region ---------------------------------------------------[Script parameters]-----------------------------------------------------
param(
    [Parameter(Mandatory=$false)]
    [string]$ExpectedVersion = "",
    [Parameter(Mandatory=$false)]
    [string]$FolderName = "ApacheJMeter"
)
#endregion

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
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
[string]$TargetPath = Join-Path -Path $DesktopPath -ChildPath $FolderName
[string]$VersionFile = Join-Path -Path $TargetPath -ChildPath "version.txt"
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
Write-ToLog "-> Looking for folder: $TargetPath"

# Check if Apache JMeter folder exists on desktop
if (!(Test-Path -Path $TargetPath)) {
    Write-ToLog "-> ERROR: Apache JMeter folder not found on desktop" "Red"
    ApplicationNotDetected
}

Write-ToLog "-> Apache JMeter folder found" "Green"

# Check if version file exists
if (Test-Path -Path $VersionFile) {
    try {
        $VersionContent = Get-Content -Path $VersionFile -Raw
        Write-ToLog "-> Version file found" "Green"
        Write-ToLog "-> Version info: $($VersionContent -replace "`r`n", ' | ')" "Cyan"
        
        # Extract version from file
        if ($VersionContent -match "Apache JMeter Version: (.+)") {
            $InstalledVersion = $matches[1].Trim()
            Write-ToLog "-> Installed version: $InstalledVersion" "Cyan"
            
            # If expected version is specified, validate it
            if ($ExpectedVersion -ne "" -and $ExpectedVersion -ne "Unknown") {
                if ($InstalledVersion -eq $ExpectedVersion) {
                    Write-ToLog "-> Version match: $InstalledVersion = $ExpectedVersion" "Green"
                    ApplicationDetected
                }
                else {
                    Write-ToLog "-> Version mismatch: $InstalledVersion != $ExpectedVersion" "Yellow"
                    ApplicationNotDetected
                }
            }
        }
    }
    catch {
        Write-ToLog "-> Warning: Could not read version file: $_" "Yellow"
    }
}
else {
    Write-ToLog "-> Version file not found (older deployment)" "Yellow"
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

# Try to detect JMeter version from JAR manifest if available
$JMeterJar = Join-Path -Path $TargetPath -ChildPath "bin\ApacheJMeter.jar"
if (Test-Path -Path $JMeterJar) {
    try {
        # Get file version info
        $JarFile = Get-Item -Path $JMeterJar
        Write-ToLog "-> JMeter JAR file size: $([math]::Round($JarFile.Length / 1MB, 2)) MB" "Cyan"
        Write-ToLog "-> JMeter JAR last modified: $($JarFile.LastWriteTime)" "Cyan"
    }
    catch {
        Write-ToLog "-> Warning: Could not read JAR file properties: $_" "Yellow"
    }
}

# Check if jmeter.bat is executable
$JMeterBat = Join-Path -Path $TargetPath -ChildPath "bin\jmeter.bat"
if (Test-Path -Path $JMeterBat) {
    $BatContent = Get-Content -Path $JMeterBat -Raw -ErrorAction SilentlyContinue
    if ($BatContent -match 'JMETER_HOME') {
        Write-ToLog "-> jmeter.bat appears to be valid (contains JMETER_HOME reference)" "Green"
    }
    else {
        Write-ToLog "-> Warning: jmeter.bat may be corrupted" "Yellow"
    }
}

Write-ToLog "-> All verification checks passed" "Green"
ApplicationDetected

#endregion
