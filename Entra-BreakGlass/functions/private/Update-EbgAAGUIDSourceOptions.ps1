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

    $sourceOptions = @($admins | ForEach-Object {
        $id = [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id')
        $displayName = [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'displayName')
        $upn = [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'userPrincipalName')
        $label = [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'label')
        if ([string]::IsNullOrWhiteSpace($label)) { $label = ('{0} <{1}>' -f $displayName, $upn) }
        [pscustomobject]@{
            Id = $id
            UserPrincipalName = $upn
            Label = $label
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Id) -and -not [string]::IsNullOrWhiteSpace($_.UserPrincipalName) })
    $sync.State.AAGUIDSourceOptions = $sourceOptions

    $combo1 = $sync.WPFAAGUIDSourceAdmin1
    $combo2 = $sync.WPFAAGUIDSourceAdmin2
    $previousLabel1 = if ($combo1 -and $combo1.SelectedItem) { [string]$combo1.SelectedItem } else { '' }
    $previousLabel2 = if ($combo2 -and $combo2.SelectedItem) { [string]$combo2.SelectedItem } else { '' }
    $previousOption1 = if ($previousLabel1) { $sourceOptions | Where-Object { $_.Label -eq $previousLabel1 } | Select-Object -First 1 } else { $null }
    $previousOption2 = if ($previousLabel2) { $sourceOptions | Where-Object { $_.Label -eq $previousLabel2 } | Select-Object -First 1 } else { $null }
    $previousId1 = if ($previousOption1) { [string](Get-EbgObjectPropertyValue -InputObject $previousOption1 -Name 'Id') } else { '' }
    $previousId2 = if ($previousOption2) { [string](Get-EbgObjectPropertyValue -InputObject $previousOption2 -Name 'Id') } else { '' }

    $sync.UI.SuppressAAGUIDSourceChange = $true
    try {
        if ($combo1) {
            $options1 = @($sourceOptions | Where-Object { [string]$_.Id -ne $previousId2 })
            $labels1 = @($options1 | ForEach-Object { [string]$_.Label })
            $combo1.ItemsSource = $null
            $combo1.DisplayMemberPath = ''
            $combo1.ItemsSource = $labels1
            if (-not [string]::IsNullOrWhiteSpace($previousLabel1) -and $labels1 -contains $previousLabel1) {
                $combo1.SelectedItem = $previousLabel1
            }
        }

        if ($combo2) {
            $options2 = @($sourceOptions | Where-Object { [string]$_.Id -ne $previousId1 })
            $labels2 = @($options2 | ForEach-Object { [string]$_.Label })
            $combo2.ItemsSource = $null
            $combo2.DisplayMemberPath = ''
            $combo2.ItemsSource = $labels2
            if (-not [string]::IsNullOrWhiteSpace($previousLabel2) -and $labels2 -contains $previousLabel2) {
                $combo2.SelectedItem = $previousLabel2
            }
        }
    }
    finally {
        $sync.UI.SuppressAAGUIDSourceChange = $false
    }

    if ($sync.WPFAAGUIDSourceAdminHint) {
        $selectedCount = @(
            if ($combo1 -and -not [string]::IsNullOrWhiteSpace([string]$combo1.SelectedItem)) { $combo1.SelectedItem }
            if ([bool]$sync.State.AAGUIDSource2Visible -and $combo2 -and -not [string]::IsNullOrWhiteSpace([string]$combo2.SelectedItem)) { $combo2.SelectedItem }
        ).Count
        $sync.WPFAAGUIDSourceAdminHint.Text = if ($admins.Count -gt 0) {
            "$($admins.Count) aktive direkte Global Administrator-konti hentet. $selectedCount AAGUID-kildekonto/konti valgt."
        }
        else {
            'Ingen Global Administrator-konti er hentet endnu. Kør Discovery eller brug Hent Global Admins.'
        }
    }
}
