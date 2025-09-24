param(
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    [Parameter(Mandatory=$true)]
    [string]$AppId,
    [Parameter(Mandatory=$true)]
    [string]$AppSecret,
    [Parameter(Mandatory=$false)]
    [string]$GroupTag
)

# Set log file path (change as needed)
if ($LogDir) {
    $LogFile = Join-Path -Path $LogDir -ChildPath "AutopilotHelper.log"
} else {
    $LogFile = Join-Path -Path $PSScriptRoot -ChildPath "AutopilotHelper.log"
}
function Write-ToLog {
    [CmdletBinding()]
    param(
        [Parameter()] [String] $LogMsg,
        [Parameter()] [String] $LogColor = "White",
        [Parameter()] [Switch] $IsHeader = $false
    )

    # Create file if doesn't exist
    if (!(Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
    }

    # If header requested
    if ($IsHeader) {
        $Log = "################################################################`n         $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) $(Get-Date -UFormat "%T")  $LogMsg`n################################################################"
    }
    else {
        $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    }

    # Echo log
    $Log | Write-Host -ForegroundColor $LogColor

    # Write log to file
    $Log | Out-File -FilePath $LogFile -Append
}

Write-ToLog "Starting Autopilot hardware hash collection..." -LogColor Cyan -IsHeader

# Validate BIOS serial number
$serial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
if ([string]::IsNullOrWhiteSpace($serial)) {
    Write-ToLog "[ERROR] Empty BIOS SerialNumber. Cannot continue." -LogColor Red
    exit 1
} else {
    Write-ToLog "[INFO] Serial: $serial" -LogColor Cyan
}

# Download and import the community script if not present
$scriptPath = "$PSScriptRoot\\Get-WindowsAutopilotInfo.ps1"
if (-not (Test-Path $scriptPath)) {
    Write-ToLog "[INFO] Downloading Get-WindowsAutopilotInfo.ps1..." -LogColor Cyan
    Save-Script -Name Get-WindowsAutopilotInfo -Path $PSScriptRoot -Force
}

# Prepare parameters for the community script
$params = @{
    TenantId   = $TenantId
    AppId      = $AppId
    AppSecret  = $AppSecret
    Online     = $true
}
if ($GroupTag) { $params['GroupTag'] = $GroupTag }

# Run the community script
Write-ToLog "[INFO] Running Get-WindowsAutopilotInfo.ps1..." -LogColor Cyan
. $scriptPath @params

Write-ToLog "[SUCCESS] Autopilot hash uploaded successfully." -LogColor Green