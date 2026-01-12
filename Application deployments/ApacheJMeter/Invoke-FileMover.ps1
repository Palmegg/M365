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

# Find apache-jmeter-*.zip file in script root
Write-ToLog "-> Looking for apache-jmeter-*.zip file in script root..."
$JMeterZips = Get-ChildItem -Path $PSScriptRoot -File -Filter "apache-jmeter-*.zip" -ErrorAction SilentlyContinue

if ($JMeterZips.Count -eq 0) {
    Write-ToLog "-> ERROR: No apache-jmeter-*.zip file found in $PSScriptRoot" "Red"
    Write-ToLog "Ending deployment script" -IsHeader
    exit 1
}

# Use the first matching ZIP file
$ZipPath = $JMeterZips[0].FullName
$ZipFileName = $JMeterZips[0].Name

Write-ToLog "-> ZIP file found: $ZipFileName" "Green"
Write-ToLog "-> Full ZIP path: $ZipPath" "Cyan"
Write-ToLog "-> Extracting to: $DesktopPath" "Cyan"

# Extract ZIP file to desktop
try {
    Write-ToLog "-> Extracting Apache JMeter ZIP file to desktop..."
    Expand-Archive -Path $ZipPath -DestinationPath $DesktopPath -Force -ErrorAction Stop
    Write-ToLog "-> Apache JMeter successfully extracted to desktop" "Green"
    
    # Verify extraction by finding the extracted folder
    $ExtractedFolderName = [System.IO.Path]::GetFileNameWithoutExtension($ZipFileName)
    $ExtractedPath = Join-Path -Path $DesktopPath -ChildPath $ExtractedFolderName
    
    if (Test-Path -Path $ExtractedPath) {
        $FileCount = (Get-ChildItem -Path $ExtractedPath -Recurse -File | Measure-Object).Count
        Write-ToLog "-> Verification successful: $FileCount files extracted" "Green"
        Write-ToLog "-> Extracted folder: $ExtractedFolderName" "Green"
    }
    else {
        Write-ToLog "-> Warning: Could not verify extracted folder at $ExtractedPath" "Yellow"
        Write-ToLog "-> ZIP extraction completed but folder structure may differ" "Yellow"
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
