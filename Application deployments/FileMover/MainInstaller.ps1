#region ---------------------------------------------------[Script parameters]-----------------------------------------------------
param(
    [Parameter(Mandatory=$true)][string]$Prefix             = "Mover",
    [Parameter(Mandatory=$false)][string]$DestinationPath   = "C:\ProgramData\CorporateFiles"
)
#endregion

#region ---------------------------------------------------[Modifiable Parameters and defaults]------------------------------------
[string]$IMELogPath                 = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
[string]$ApplicationLogName         = "#${Prefix}_FileMover"
[string]$SourcePath                 = $PSScriptRoot
[string]$DetectorContent = @"
FileMover Detection File
========================
Installation Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Source Path: $SourcePath
Destination Path: $DestinationPath
Installed By: $env:USERNAME
Computer Name: $env:COMPUTERNAME
"@
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
function Copy-FilesFromSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    
    try {
        # Create destination directory if it doesn't exist
        if (!(Test-Path -Path $Destination)) {
            Write-ToLog "Creating destination directory: $Destination" -LogColor Cyan
            New-Item -Path $Destination -ItemType Directory -Force | Out-Null
        }
        
        # Get all files and folders from source, excluding the script itself and log files
        $Items = Get-ChildItem -Path $Source -Recurse -Force | Where-Object {
            $_.Name -ne $MyInvocation.ScriptName -and 
            $_.Extension -ne '.log' -and
            $_.Name -ne 'README.txt'
        }
        
        if ($Items.Count -eq 0) {
            Write-ToLog "No files found to copy in source directory: $Source" -LogColor Yellow
            return $false
        }
        
        Write-ToLog "Found $($Items.Count) items to copy" -LogColor Cyan
        
        $CopiedCount = 0
        $FailedCount = 0
        
        foreach ($Item in $Items) {
            try {
                # Calculate relative path
                $RelativePath = $Item.FullName.Substring($Source.Length)
                $DestinationItem = Join-Path -Path $Destination -ChildPath $RelativePath
                
                if ($Item.PSIsContainer) {
                    # Create directory
                    if (!(Test-Path -Path $DestinationItem)) {
                        New-Item -Path $DestinationItem -ItemType Directory -Force | Out-Null
                        Write-ToLog "Created directory: $DestinationItem" -LogColor Green
                    }
                }
                else {
                    # Copy file
                    $DestinationFolder = Split-Path -Path $DestinationItem -Parent
                    if (!(Test-Path -Path $DestinationFolder)) {
                        New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
                    }
                    
                    Copy-Item -Path $Item.FullName -Destination $DestinationItem -Force
                    Write-ToLog "Copied: $($Item.Name) -> $DestinationItem" -LogColor Green
                    $CopiedCount++
                }
            }
            catch {
                Write-ToLog "Failed to copy $($Item.FullName): $($_.Exception.Message)" -LogColor Red
                $FailedCount++
            }
        }
        
        Write-ToLog "Copy operation completed. Copied: $CopiedCount | Failed: $FailedCount" -LogColor Cyan
        
        if ($FailedCount -eq 0) {
            return $true
        }
        else {
            return $false
        }
    }
    catch {
        Write-ToLog "Error in Copy-FilesFromSource: $($_.Exception.Message)" -LogColor Red
        return $false
    }
}
function Test-FileCopySuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Destination
    )
    
    if (Test-Path -Path $Destination) {
        $FileCount = (Get-ChildItem -Path $Destination -Recurse -File | Measure-Object).Count
        Write-ToLog "Verification: Found $FileCount files in destination" -LogColor Cyan
        return ($FileCount -gt 0)
    }
    return $false
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
Write-ToLog "FileMover Started" -IsHeader -LogColor Cyan
Write-ToLog "Source Path: $SourcePath" -LogColor White
Write-ToLog "Destination Path: $DestinationPath" -LogColor White

# Validate source path
if (!(Test-Path -Path $SourcePath)) {
    Write-ToLog "ERROR: Source path does not exist: $SourcePath" -LogColor Red
    exit 1
}

# Perform file copy operation
Write-ToLog "Starting file copy operation..." -LogColor Cyan
$CopyResult = Copy-FilesFromSource -Source $SourcePath -Destination $DestinationPath

if ($CopyResult) {
    Write-ToLog "File copy operation completed successfully" -LogColor Green
    
    # Verify the copy
    if (Test-FileCopySuccess -Destination $DestinationPath) {
        Write-ToLog "Verification successful - Files are present in destination" -LogColor Green
        
        # Create detector file
        try {
            $DetectorFile = Join-Path -Path $DestinationPath -ChildPath "detector.log"
            $DetectorContent | Out-File -FilePath $DetectorFile -Force
            Write-ToLog "Created detector file: $DetectorFile" -LogColor Green
        }
        catch {
            Write-ToLog "Warning: Failed to create detector file: $($_.Exception.Message)" -LogColor Yellow
        }
        
        Write-ToLog "FileMover Completed" -IsHeader -LogColor Cyan
        exit 0
    }
    else {
        Write-ToLog "Verification failed - No files found in destination" -LogColor Red
        Write-ToLog "FileMover exiting" -IsHeader -LogColor red
        exit 1
    }
}
else {
    Write-ToLog "File copy operation failed" -LogColor Red
    Write-ToLog "FileMover exiting" -IsHeader -LogColor red
    exit 1
}
#endregion

