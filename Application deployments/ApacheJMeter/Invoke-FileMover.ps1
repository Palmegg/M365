#region ---------------------------------------------------[Script parameters]-----------------------------------------------------
param(
    [Parameter(Mandatory=$false)]
    [string]$DestinationFolderName = "ApacheJMeter",
    [Parameter(Mandatory=$false)]
    [string]$Version = "Unknown"
)
#endregion

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$CorpDataPath           = "$env:LOCALAPPDATA\IntuneManagementLogs"
[string]$ApplicationLogName     = "#ApacheJMeter_Deployment"
[string]$SourceFolderName       = "ApacheJMeter"
#endregion

#region ---------------------------------------------------[Static Variables]------------------------------------------------------
[string]$logpath = "$($CorpDataPath)"
if (!(Test-Path -Path $logpath)) {
    New-Item -Path $logpath -ItemType Directory -Force | Out-Null
}
[string]$Script:LogFile = "$($logpath)\$($ApplicationLogName).log"
[string]$SourcePath = Join-Path -Path $PSScriptRoot -ChildPath $SourceFolderName
[string]$DesktopPath = [Environment]::GetFolderPath("Desktop")
[string]$DestinationPath = Join-Path -Path $DesktopPath -ChildPath $DestinationFolderName
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
Write-ToLog "-> Version: $Version"

# Validate source folder exists
if (!(Test-Path -Path $SourcePath)) {
    Write-ToLog "-> ERROR: Source folder not found: $SourcePath" "Red"
    Write-ToLog "Ending deployment script" -IsHeader
    exit 1
}

Write-ToLog "-> Source folder found: $SourcePath"
Write-ToLog "-> Destination: $DestinationPath"

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
        
        # Create version file for tracking
        $VersionFile = Join-Path -Path $DestinationPath -ChildPath "version.txt"
        try {
            "Apache JMeter Version: $Version`nDeployed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`nDeployed by: $env:UserName" | Out-File -FilePath $VersionFile -Force
            Write-ToLog "-> Version file created: $Version" "Green"
        }
        catch {
            Write-ToLog "-> Warning: Could not create version file: $_" "Yellow"
        }
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
