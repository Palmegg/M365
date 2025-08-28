#region ---------------------------------------------------[Script parameters]-----------------------------------------------------
param(
    [Parameter(Mandatory=$true)]
    [string]$CustomerPrefix
)
#endregion

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$CorpDataPath           = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName = "#${CustomerPrefix}_DeviceRenamer"

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

    #Create file if doesn't exist
    if (!(Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null

        <#
        #Set ACL for users on logfile
        $NewAcl = Get-Acl -Path $LogFile
        $identity = New-Object System.Security.Principal.SecurityIdentifier S-1-5-11
        $fileSystemRights = "Modify"
        $type = "Allow"
        $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
        $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
        $NewAcl.SetAccessRule($fileSystemAccessRule)
        Set-Acl -Path $LogFile -AclObject $NewAcl
        #>
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

#region ---------------------------------------------------[Script Execution]------------------------------------------------------

#Configure console output encoding
$null = cmd /c '' #Tip for ISE
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

# ReadMe file with disclaimer and instructions
$ReadMeFile = "$LogPath\README.txt"
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

Write-ToLog "Starting installation script" -IsHeader
Write-ToLog "-> Running as: $env:UserName"

# Check if customerprefix is empty
if (-not $CustomerPrefix) {
    Write-ToLog "-> No customer prefix has been specified as an argument. The script is terminating." "Red"
    exit 1
}
else {
    Write-ToLog "-> Customer prefix: $CustomerPrefix"

    # Collect serial number
    $Serial = (Get-WmiObject Win32_BIOS).SerialNumber

    # Collect current device name
    $CurrentDeviceName = $env:COMPUTERNAME
    Write-ToLog "-> Existing device name: $CurrentDeviceName"

    # Check if serial number is longer than 8 characters and shorten it if necessary
    if ($Serial.Length -gt 8) {
    $Serial = $Serial.Substring(0, 8)
    Write-ToLog "-> Serial number is longer than 8 characters!!"
    Write-ToLog "-> The serial number has been shortened to: $Serial"
    }

    # Create new device name based on customer prefix and serial number
    $NewDeviceName = $CustomerPrefix + "-" + $Serial

    try {
        Write-ToLog "-> Renaming device: $NewDeviceName"
        # Rename computer
        Rename-Computer -NewName $NewDeviceName
        Write-ToLog "-> DeviceRenamer successfull" "Green"
    }
    catch {
        # Write error to log
        write-toLog "-> An error occurred while trying to rename the computer." "Red"
        write-toLog "-> Error message: $_" "Red"
        Write-ToLog "Ending installation script" -IsHeader
        exit 1
    }

    Write-ToLog "Ending installation script" -IsHeader
    # Return code 3010 // Intune sees this return code as "Soft Reboot"
    return 3010
}