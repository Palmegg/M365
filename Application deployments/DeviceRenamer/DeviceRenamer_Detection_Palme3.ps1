#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
$Prefix = "Palme3"
#endregion

#region ---------------------------------------------------[Functions]-------------------------------------------------------------

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$CorpDataPath           = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName = "#${Prefix}_DeviceRenamer"
#endregion

#region ---------------------------------------------------[Static Variables]------------------------------------------------------
[string]$logpath = "$($CorpDataPath)"
if (!(Test-Path -Path $logpath)) {
    New-Item -Path $logpath -ItemType Directory -Force | Out-Null
}
[string]$Script:LogFile = "$($logpath)\$($ApplicationLogName).log"
#endregion

function Write-ToLog {

    [CmdletBinding()]
    param(
        [Parameter()] [String] $LogMsg,
        [Parameter()] [String] $LogColor = "White",
        [Parameter()] [Switch] $IsHeader = $false
    )

    #Create file if it doesn't exist
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
    # Set STDOUT to a value so it is NOT empty
    Write-Host "Random output to mark as installed"
    # Return 0 // Marked as Installed
    exit 0
}
function ApplicationNotDetected {
    # Return 1 (STDOUT empty) // Marked as Not Installed
    exit 1
}

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

Write-ToLog "Starting detection script" -IsHeader
Write-ToLog "-> Running as: $env:UserName"

# Get the current computer name
$CurrentDeviceName = $env:COMPUTERNAME
Write-ToLog "-> Current name: $CurrentDeviceName"

# Get the serial number from BIOS
$Serial = (Get-WmiObject Win32_BIOS).SerialNumber

# Check if the serial number is longer than 8 characters and shorten it if necessary
if ($Serial.Length -gt 8) {
    $Serial = $Serial.Substring(0, 8)
    Write-ToLog "-> Serial number is longer than 8 characters!!"
    Write-ToLog "-> The serial number has been shortened to: $Serial"
}
else {
    Write-ToLog "-> Serial number: $Serial"
}

# Define the new name with a dash
$FinalDeviceName = $Prefix + "-" + $Serial
Write-ToLog "-> Expected name: $FinalDeviceName"

# Check if the computer name matches the expected name
if ($FinalDeviceName -match $CurrentDeviceName) {
    Write-ToLog "-> Computer name matches the expected name." "Green"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationDetected
}
else {
    Write-ToLog "-> Computer name does not match the expected name." "Red"
    Write-ToLog "Ending detection script" -IsHeader
    ApplicationNotDetected
}