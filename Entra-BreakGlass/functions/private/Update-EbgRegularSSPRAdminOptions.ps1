function Update-EbgRegularSSPRAdminOptions {
    [CmdletBinding()]
    param()

    if (-not $sync.Form) { return }
    if (-not $sync.Form.Dispatcher.CheckAccess()) {
        [void]$sync.Form.Dispatcher.Invoke([System.Action]{ Update-EbgRegularSSPRAdminOptions | Out-Null })
        return
    }

    $admins = @($sync.State.ActiveGlobalAdministrators)
    if ($admins.Count -lt 1 -and $sync.State.Discovery) {
        $admins = @(Get-EbgObjectPropertyValue -InputObject $sync.State.Discovery -Name 'ActiveGlobalAdministrators')
    }

    foreach ($comboName in @('WPFRegularSSPRAdmin1','WPFRegularSSPRAdmin2')) {
        $combo = $sync[$comboName]
        if (-not $combo) { continue }

        $previousId = if ($combo.SelectedItem) { [string](Get-EbgObjectPropertyValue -InputObject $combo.SelectedItem -Name 'id') } else { '' }
        $combo.ItemsSource = $null
        $combo.ItemsSource = @($admins)
        $combo.DisplayMemberPath = 'label'

        if (-not [string]::IsNullOrWhiteSpace($previousId)) {
            $match = @($admins | Where-Object { [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id') -eq $previousId } | Select-Object -First 1)
            if ($match.Count -gt 0) { $combo.SelectedItem = $match[0] }
        }
    }

    if ($sync.WPFRegularSSPRAdminHint) {
        $sync.WPFRegularSSPRAdminHint.Text = if ($admins.Count -gt 0) {
            "$($admins.Count) aktive direkte Global Administrator-konti hentet. Vælg de to konti der skal ekskluderes fra regular SSPR-gruppen."
        }
        else {
            'Ingen Global Administrator-konti er hentet endnu. Brug knappen eller kør Discovery.'
        }
    }
}
