#region ---------------------------------------------------[Script parameters]-----------------------------------------------------
#endregion

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$ServiceName                = "Sysmon64"
[string]$Prefix                     = "Sysmon"
[string]$CorpDataPath               = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName         = "#${Prefix}"
[string]$ProductName                = "Sysmon64"
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

Write-ToLog "Starting detection script for Sysmon64" -IsHeader
Write-ToLog "Running as: $env:UserName"

# Check if Sysmon64 service exists and is running
try {
    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    
    if ($service) {
        Write-ToLog "Sysmon64 service detected" "Cyan"
        Write-ToLog "Service Status: $($service.Status)" "Cyan"
        Write-ToLog "Service DisplayName: $($service.DisplayName)" "Cyan"
        Write-ToLog "Service StartType: $($service.StartType)" "Cyan"
        
        if ($service.Status -eq 'Running') {
            Write-ToLog "Sysmon64 service is running." "Green"
            Write-ToLog "Ending detection script" -IsHeader
            ApplicationDetected
        } else {
            Write-ToLog "Sysmon64 service exists but is not running (Status: $($service.Status))." "Yellow"
            Write-ToLog "Ending detection script" -IsHeader
            ApplicationNotDetected
        }
    }
} catch {
    Write-ToLog "Sysmon64 service not detected. Error: $($_.Exception.Message)" "Red"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationNotDetected
}

#endregion
 