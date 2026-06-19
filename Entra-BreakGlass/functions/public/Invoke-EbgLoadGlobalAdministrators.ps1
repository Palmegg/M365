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

    Invoke-EbgRunspace -ScriptBlock {
        Write-EbgStatus -Busy -Message 'Henter aktive Global Administrator-konti...'
        Ensure-EbgGraphContext
        Write-EbgLog -Message 'Henter direkte Global Administrator role assignments fra Microsoft Graph...'
        $admins = @(Get-EbgActiveGlobalAdministrators)
        $sync.State.ActiveGlobalAdministrators = $admins
        if ($sync.State.Discovery) {
            $sync.State.Discovery | Add-Member -MemberType NoteProperty -Name ActiveGlobalAdministrators -Value $admins -Force
        }
        Invoke-EbgUIThread -ScriptBlock {
            Update-EbgRegularSSPRAdminOptions
            Update-EbgAAGUIDSourceOptions
            Update-EbgUIState | Out-Null
        } -Wait
        Write-EbgStatus -Message "Hentede $($admins.Count) aktive direkte Global Administrator-konti."
    }
}
