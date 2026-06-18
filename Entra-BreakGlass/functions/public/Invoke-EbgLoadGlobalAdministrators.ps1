function Invoke-EbgLoadGlobalAdministrators {
    [CmdletBinding()]
    param()

    if (-not $sync.State.GraphConnected -and -not $sync.App.Mock) {
        [System.Windows.MessageBox]::Show("Du skal først forbinde til Microsoft Graph under trinnet 'Forbind'.", $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }
    if ($sync.UI.ProcessRunning) {
        [System.Windows.MessageBox]::Show('Der kører allerede en opgave. Vent til den er færdig.', $sync.App.Name, 'OK', 'Information') | Out-Null
        return
    }

    $sync.UI.ProcessRunning = $true
    if ($sync.WPFRefreshRegularSSPRAdmins) { $sync.WPFRefreshRegularSSPRAdmins.IsEnabled = $false }
    if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $true }

    try {
        Write-EbgStatus -Busy -Message 'Henter aktive Global Administrator-konti...'
        [System.Windows.Forms.Application]::DoEvents()
        Ensure-EbgGraphContext
        $admins = @(Get-EbgActiveGlobalAdministrators)
        $sync.State.ActiveGlobalAdministrators = $admins
        if ($sync.State.Discovery) {
            $sync.State.Discovery | Add-Member -MemberType NoteProperty -Name ActiveGlobalAdministrators -Value $admins -Force
        }
        Update-EbgRegularSSPRAdminOptions
        Write-EbgStatus -Message "Hentede $($admins.Count) aktive direkte Global Administrator-konti."
    }
    catch {
        $message = ConvertTo-EbgRedactedError -ErrorRecord $_
        Write-EbgLog -Level ERROR -Message $message
        Write-EbgStatus -Message 'Kunne ikke hente Global Administrator-konti.'
        [System.Windows.MessageBox]::Show($message, $sync.App.Name, 'OK', 'Error') | Out-Null
    }
    finally {
        $sync.UI.ProcessRunning = $false
        if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $false }
        if ($sync.WPFRefreshRegularSSPRAdmins) { $sync.WPFRefreshRegularSSPRAdmins.IsEnabled = $true }
        Update-EbgUIState | Out-Null
    }
}
