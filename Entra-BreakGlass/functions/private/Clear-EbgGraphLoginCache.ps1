function Clear-EbgGraphLoginCache {
    [CmdletBinding()]
    param()

    $backupRoot = Join-Path -Path $sync.App.OutputRoot -ChildPath ('GraphLoginCacheBackup-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $mgProfilePath = Join-Path -Path $HOME -ChildPath '.mg'
    if (Test-Path -LiteralPath $mgProfilePath) {
        $target = Join-Path -Path $backupRoot -ChildPath 'home-dot-mg'
        try {
            Move-Item -LiteralPath $mgProfilePath -Destination $target -Force -ErrorAction Stop
            Write-EbgLog -Message "Graph PowerShell profile cache moved to backup: $target"
        }
        catch {
            Write-EbgLog -Level WARN -Message "Kunne ikke flytte Graph PowerShell profile cache '$mgProfilePath'. $($_.Exception.Message)"
        }
    }

    $identityServicePath = Join-Path -Path $env:LOCALAPPDATA -ChildPath '.IdentityService'
    if (Test-Path -LiteralPath $identityServicePath) {
        $target = Join-Path -Path $backupRoot -ChildPath 'identityservice-msal'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Get-ChildItem -LiteralPath $identityServicePath -Filter 'mg.msal.cache*' -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Move-Item -LiteralPath $_.FullName -Destination (Join-Path -Path $target -ChildPath $_.Name) -Force -ErrorAction Stop
                Write-EbgLog -Message "Graph MSAL cache moved to backup: $($_.Name)"
            }
            catch {
                Write-EbgLog -Level WARN -Message "Kunne ikke flytte Graph MSAL cache '$($_.FullName)'. $($_.Exception.Message)"
            }
        }
    }
}
