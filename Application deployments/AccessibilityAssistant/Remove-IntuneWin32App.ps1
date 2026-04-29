param(
    [string]$AppNamePattern,

    [string]$IntuneAppId,

    [switch]$DeleteAppKey,

    [switch]$DeleteGRS,

    [switch]$ListAll
)

# GRS = Global Re-evaluation Schedule
# Path: HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\{IntuneAppId}\GRS\{HashedValue}
# GRS contains a string value (default) with the Intune App ID - only exists for apps in retry/failed state

$BasePath = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'

if (-not $DeleteAppKey -and -not $DeleteGRS -and -not $ListAll) {
    Write-Host "Specify -DeleteAppKey to delete the app registration, -DeleteGRS to delete the GRS retry timer, or -ListAll to list all GRS entries."
    Write-Host ""
    Write-Host "Search by app name:"
    Write-Host "  .\Remove-IntuneWin32App.ps1 -AppNamePattern 'Accessibility' -DeleteGRS"
    Write-Host "  .\Remove-IntuneWin32App.ps1 -AppNamePattern 'Office' -DeleteGRS"
    Write-Host ""
    Write-Host "Search by Intune AppId GUID directly:"
    Write-Host "  .\Remove-IntuneWin32App.ps1 -IntuneAppId '596a36a4-7a9d-4477-aa5b-7f4d09beaf23' -DeleteGRS"
    Write-Host ""
    Write-Host "List all GRS entries (use to find app when name search fails):"
    Write-Host "  .\Remove-IntuneWin32App.ps1 -ListAll"
    exit 1
}

# Validate that AppNamePattern or IntuneAppId is provided when not just listing
if (-not $ListAll -and [string]::IsNullOrWhiteSpace($AppNamePattern) -and [string]::IsNullOrWhiteSpace($IntuneAppId)) {
    Write-Host "Error: Either -AppNamePattern or -IntuneAppId must be specified."
    exit 1
}

# Normalize IntuneAppId - remove braces if present
if (-not [string]::IsNullOrWhiteSpace($IntuneAppId)) {
    $IntuneAppId = $IntuneAppId.Trim('{').Trim('}').Trim()
}

# List ALL GRS entries regardless of app name (useful for finding failed apps)
if ($ListAll) {
    Write-Host "Listing all GRS entries under $BasePath"
    Write-Host ""

    $grsEntryCount = 0

    if (Test-Path $BasePath) {
        Get-ChildItem -Path $BasePath -ErrorAction SilentlyContinue | ForEach-Object {
            $appIdPath = $_.PSPath
            $appIdName = $_.PSChildName

            $props = Get-ItemProperty -Path $appIdPath -ErrorAction SilentlyContinue
            $displayName = $props.DisplayName

            $grsBasePath = Join-Path $appIdPath 'GRS'
            if (Test-Path $grsBasePath) {
                $grsEntryCount++
                Write-Host "=== App Registration ==="
                Write-Host "  IntuneAppId: $appIdName"
                Write-Host "  DisplayName: $displayName"
                Write-Host "  Path: $appIdPath"

                Get-ChildItem -Path $grsBasePath -ErrorAction SilentlyContinue | ForEach-Object {
                    $grsHashPath = $_.PSPath
                    $grsHashProps = Get-ItemProperty -Path $grsHashPath -ErrorAction SilentlyContinue
                    $grsValue = $grsHashProps.'(default)'
                    Write-Host "  GRS Hash: $($_.PSChildName)"
                    Write-Host "  GRS DefaultValue (Intune App ID): $grsValue"
                    Write-Host "  GRS Full Path: $grsHashPath"
                }
                Write-Host ""
            }
        }
    }

    if ($grsEntryCount -eq 0) {
        Write-Host "No GRS entries found."
    } else {
        Write-Host "Found $grsEntryCount GRS entry/entries."
    }
    exit 0
}

Write-Host "Searching in: $BasePath"
if (-not [string]::IsNullOrWhiteSpace($AppNamePattern)) {
    Write-Host "Pattern: $AppNamePattern (by name)"
}
if (-not [string]::IsNullOrWhiteSpace($IntuneAppId)) {
    Write-Host "IntuneAppId: $IntuneAppId (by GUID)"
}
Write-Host ""

if (Test-Path $BasePath) {
    $items = Get-ChildItem -Path $BasePath -ErrorAction SilentlyContinue
    $itemsProcessed = 0

    foreach ($item in $items) {
        $appIdPath = $item.PSPath
        $appIdName = $item.PSChildName

        $props = Get-ItemProperty -Path $appIdPath -ErrorAction SilentlyContinue

        # Determine if this key matches
        $isMatch = $false
        $matchReason = $null

        # Check by IntuneAppId first (most reliable)
        if (-not [string]::IsNullOrWhiteSpace($IntuneAppId)) {
            if ($appIdName -eq $IntuneAppId) {
                $isMatch = $true
                $matchReason = "IntuneAppId match"
            }
        }

        # Check by AppNamePattern
        if (-not $isMatch -and -not [string]::IsNullOrWhiteSpace($AppNamePattern)) {
            if ($appIdName -match $AppNamePattern) {
                $isMatch = $true
                $matchReason = "AppId name match"
            }
            if ($props.DisplayName -match $AppNamePattern) {
                $isMatch = $true
                $matchReason = "DisplayName match"
            }
        }

        # Search deeper if not found at root - also check GRS default value
        if (-not $isMatch -and -not [string]::IsNullOrWhiteSpace($AppNamePattern)) {
            $subItems = Get-ChildItem -Path $appIdPath -Recurse -ErrorAction SilentlyContinue
            foreach ($sub in $subItems) {
                $subProps = Get-ItemProperty -Path $sub.PSPath -ErrorAction SilentlyContinue
                if ($subProps.DisplayName -match $AppNamePattern) {
                    $isMatch = $true
                    $matchReason = "Subkey DisplayName match"
                    break
                }
                # Also check if GRS default value contains the app name pattern
                if ($subProps.'(default)' -match $AppNamePattern) {
                    $isMatch = $true
                    $matchReason = "GRS default value match"
                    break
                }
            }
        }

        if ($isMatch) {
            $itemsProcessed++
            $displayName = if ($props.DisplayName) { $props.DisplayName } else { $appIdName }
            Write-Host "Found app: $displayName"
            Write-Host "  Match reason: $matchReason"
            Write-Host "  IntuneAppId: $appIdName"
            Write-Host "  Path: $appIdPath"

            if ($DeleteGRS) {
                $grsBasePath = Join-Path $appIdPath 'GRS'
                if (Test-Path $grsBasePath) {
                    Write-Host "  Found GRS folder, checking contents..."
                    $grsItems = Get-ChildItem -Path $grsBasePath -ErrorAction SilentlyContinue
                    foreach ($grsItem in $grsItems) {
                        $grsHashPath = $grsItem.PSPath
                        $grsHashProps = Get-ItemProperty -Path $grsHashPath -ErrorAction SilentlyContinue
                        $grsValue = $grsHashProps.'(default)'
                        Write-Host "    GRS hash: $($grsItem.PSChildName)"
                        Write-Host "    GRS default value (Intune App ID): $grsValue"
                        Write-Host "    Deleting GRS hash folder: $grsHashPath"
                        Remove-Item -Path $grsHashPath -Recurse -Force
                        Write-Host "    Deleted."
                    }
                    Remove-Item -Path $grsBasePath -Force -ErrorAction SilentlyContinue
                } else {
                    Write-Host "  No GRS folder found (app may not be in failed/retry state)."
                }
            }

            if ($DeleteAppKey) {
                Write-Host "  Deleting app registration: $appIdPath"
                Remove-Item -Path $appIdPath -Recurse -Force
                Write-Host "  App registration deleted."
            }
        }
    }

    if ($itemsProcessed -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($IntuneAppId)) {
            Write-Host "No app found with IntuneAppId '$IntuneAppId' under $BasePath"
        } else {
            Write-Host "No app matching '$AppNamePattern' found under $BasePath"
        }
        Write-Host "Try running with -ListAll to see all GRS entries and identify the app manually."
    } else {
        Write-Host "Processed $itemsProcessed app(s)."
    }
} else {
    Write-Host "Base path not found: $BasePath"
}

# Restart Intune Management Extension service
$service = Get-Service -Name 'IntuneManagementExtension' -ErrorAction SilentlyContinue
if ($service) {
    Stop-Service -Name 'IntuneManagementExtension' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Start-Service -Name 'IntuneManagementExtension' -ErrorAction SilentlyContinue
    Write-Host "IntuneManagementExtension service restarted."
}