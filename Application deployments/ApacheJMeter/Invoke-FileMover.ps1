#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$CorpDataPath           = "$env:LOCALAPPDATA\IntuneManagementLogs"
[string]$ApplicationLogName     = "#ApacheJMeter_Deployment"
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

Write-ToLog "Starting Apache JMeter deployment script" -IsHeader
Write-ToLog "-> Running as: $env:UserName"
Write-ToLog "-> Running from: $PSScriptRoot"

# Find apache-jmeter-* folder in script root
Write-ToLog "-> Looking for apache-jmeter-* folder in script root..."
$JMeterFolders = Get-ChildItem -Path $PSScriptRoot -Directory -Filter "apache-jmeter-*" -ErrorAction SilentlyContinue

if ($JMeterFolders.Count -eq 0) {
    Write-ToLog "-> ERROR: No apache-jmeter-* folder found in $PSScriptRoot" "Red"
    Write-ToLog "Ending deployment script" -IsHeader
    exit 1
}

# Use the first matching folder
$SourcePath = $JMeterFolders[0].FullName
$SourceFolderName = $JMeterFolders[0].Name
$DestinationPath = Join-Path -Path $DesktopPath -ChildPath $SourceFolderName

Write-ToLog "-> Source folder found: $SourceFolderName" "Green"
Write-ToLog "-> Full source path: $SourcePath" "Cyan"
Write-ToLog "-> Destination: $DestinationPath" "Cyan"

# Check if destination already exists
if (Test-Path -Path $DestinationPath) {
    Write-ToLog "-> Apache JMeter folder already exists on desktop, removing old version..." "Yellow"
    try {
        Remove-Item -Path $DestinationPath -Recurse -Force -ErrorAction Stop
        Write-ToLog "-> Old version removed successfully" "Green"
    }
    catch {
        Write-ToLog "-> ERROR: Failed to remove old version: $_" "Red"
        Write-ToLog "Ending deployment script" -IsHeader
        exit 1
    }
}

# Copy Apache JMeter folder to user's desktop
try {
    Write-ToLog "-> Copying Apache JMeter folder to desktop..."
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
    Write-ToLog "-> Apache JMeter successfully deployed to desktop" "Green"
    # Verify deployment
    if (Test-Path -Path $DestinationPath) {
        $FileCount = (Get-ChildItem -Path $DestinationPath -Recurse -File | Measure-Object).Count
        Write-ToLog "-> Verification successful: $FileCount files deployed" "Green"
    }
    else {
        Write-ToLog "-> ERROR: Verification failed - destination folder not found" "Red"
        Write-ToLog "Ending deployment script" -IsHeader
        exit 1
    }
}
catch {
    Write-ToLog "-> ERROR: Failed to copy Apache JMeter folder: $_" "Red"
    Write-ToLog "Ending deployment script" -IsHeader
    exit 1
}

Write-ToLog "Ending deployment script" -IsHeader
exit 0
#endregion
