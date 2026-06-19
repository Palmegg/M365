function Update-EbgAAGUIDSourceOptions {
    [CmdletBinding()]
    param()

    if (-not $sync.Form) { return }
    if (-not $sync.Form.Dispatcher.CheckAccess()) {
        [void]$sync.Form.Dispatcher.Invoke([System.Action]{ Update-EbgAAGUIDSourceOptions | Out-Null })
        return
    }

    $admins = @($sync.State.ActiveGlobalAdministrators)
    if ($admins.Count -lt 1 -and $sync.State.Discovery) {
        $admins = @(Get-EbgObjectPropertyValue -InputObject $sync.State.Discovery -Name 'ActiveGlobalAdministrators')
    }

    if ($sync.WPFAAGUIDSourceAdmin2Row) {
        $sync.WPFAAGUIDSourceAdmin2Row.Visibility = if ([bool]$sync.State.AAGUIDSource2Visible) { 'Visible' } else { 'Collapsed' }
    }

    $combo1 = $sync.WPFAAGUIDSourceAdmin1
    $combo2 = $sync.WPFAAGUIDSourceAdmin2
    $previousId1 = if ($combo1 -and $combo1.SelectedItem) { [string](Get-EbgObjectPropertyValue -InputObject $combo1.SelectedItem -Name 'id') } else { '' }
    $previousId2 = if ($combo2 -and $combo2.SelectedItem) { [string](Get-EbgObjectPropertyValue -InputObject $combo2.SelectedItem -Name 'id') } else { '' }

    $sync.UI.SuppressAAGUIDSourceChange = $true
    try {
        if ($combo1) {
            $options1 = @($admins | Where-Object { [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id') -ne $previousId2 })
            $combo1.ItemsSource = $null
            $combo1.ItemsSource = $options1
            $combo1.DisplayMemberPath = 'label'
            if (-not [string]::IsNullOrWhiteSpace($previousId1)) {
                $match1 = @($options1 | Where-Object { [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id') -eq $previousId1 } | Select-Object -First 1)
                if ($match1.Count -gt 0) { $combo1.SelectedItem = $match1[0] }
            }
        }

        if ($combo2) {
            $options2 = @($admins | Where-Object { [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id') -ne $previousId1 })
            $combo2.ItemsSource = $null
            $combo2.ItemsSource = $options2
            $combo2.DisplayMemberPath = 'label'
            if (-not [string]::IsNullOrWhiteSpace($previousId2)) {
                $match2 = @($options2 | Where-Object { [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id') -eq $previousId2 } | Select-Object -First 1)
                if ($match2.Count -gt 0) { $combo2.SelectedItem = $match2[0] }
            }
        }
    }
    finally {
        $sync.UI.SuppressAAGUIDSourceChange = $false
    }

    if ($sync.WPFAAGUIDSourceAdminHint) {
        $selectedCount = @(
            if ($combo1 -and $combo1.SelectedItem) { $combo1.SelectedItem }
            if ([bool]$sync.State.AAGUIDSource2Visible -and $combo2 -and $combo2.SelectedItem) { $combo2.SelectedItem }
        ).Count
        $sync.WPFAAGUIDSourceAdminHint.Text = if ($admins.Count -gt 0) {
            "$($admins.Count) aktive direkte Global Administrator-konti hentet. $selectedCount AAGUID-kildekonto/konti valgt."
        }
        else {
            'Ingen Global Administrator-konti er hentet endnu. Kør Discovery eller brug Hent Global Admins.'
        }
    }
}
