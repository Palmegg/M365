#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$IMELogPath                   = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$Prefix                       = "Palme3" # <- Change prefix as needed!
[string]$DestinationPath              = "C:\DownloadsFileMover" # <- Change destination path as needed!
[string]$ApplicationLogName           = "#${Prefix}_FileMover"
[string]$DetectorFileName             = "detector.log"
#endregion

#region ---------------------------------------------------[Static Variables]------------------------------------------------------
[string]$logpath = "$($IMELogPath)"
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

    #Create file if doesn't exist
    if (!(Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
    }

    #If header requested
    if ($IsHeader) {
        $Log = "################################################################`n         $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) $(Get-Date -UFormat "%T")  $LogMsg`n################################################################"
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
    exit 0
}

function ApplicationNotDetected {
    exit 1
}

function Test-DetectorFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$FileName
    )
    
    try {
        $DetectorFilePath = Join-Path -Path $Path -ChildPath $FileName
        
        if (Test-Path -Path $DetectorFilePath) {
            Write-ToLog "Detector file found: $DetectorFilePath" -LogColor Green
            
            # Read and log detector file content
            try {
                $Content = Get-Content -Path $DetectorFilePath -Raw
                Write-ToLog "Detector file content:`n$Content" -LogColor Cyan
            }
            catch {
                Write-ToLog "Could not read detector file content: $($_.Exception.Message)" -LogColor Yellow
            }
            
            return $true
        }
        else {
            Write-ToLog "Detector file not found: $DetectorFilePath" -LogColor Red
            return $false
        }
    }
    catch {
        Write-ToLog "Error checking for detector file: $($_.Exception.Message)" -LogColor Red
        return $false
    }
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

# Start logging
Write-ToLog "FileMover Detection Started" -IsHeader -LogColor Cyan
Write-ToLog "Detection Path: $DestinationPath" -LogColor White
Write-ToLog "Looking for: $DetectorFileName" -LogColor White

# Check if destination path exists
if (!(Test-Path -Path $DestinationPath)) {
    Write-ToLog "ERROR: Destination path does not exist: $DestinationPath" -LogColor Red
    Write-ToLog "Detection Completed - Not Detected" -IsHeader -LogColor Red
    ApplicationNotDetected
}

# Check for detector file
Write-ToLog "Checking for detector file..." -LogColor Cyan
$DetectionResult = Test-DetectorFile -Path $DestinationPath -FileName $DetectorFileName

if ($DetectionResult) {
    Write-ToLog "Installation detected successfully" -LogColor Green
    Write-ToLog "Detection Completed - Detected" -IsHeader -LogColor Green
    ApplicationDetected
}
else {
    Write-ToLog "Installation not detected" -LogColor Red
    Write-ToLog "Detection Completed - Not Detected" -IsHeader -LogColor Red
    ApplicationNotDetected
}
#endregion
