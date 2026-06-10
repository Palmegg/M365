function Show-NetIPCreatedPasswordsOnce {
    [CmdletBinding()]
    param([object[]] $CreatedPasswords)

    if (-not $CreatedPasswords -or $CreatedPasswords.Count -eq 0) { return }
    $sync.Form.Dispatcher.Invoke([System.Action]{
        $window = New-Object System.Windows.Window
        $window.Title = 'Midlertidige adgangskoder - vises kun én gang'
        $window.Width = 720
        $window.Height = 430
        $window.WindowStartupLocation = 'CenterOwner'
        $window.Owner = $sync.Form
        $window.Topmost = $true
        $panel = New-Object System.Windows.Controls.DockPanel
        $panel.Margin = '16'
        $warning = New-Object System.Windows.Controls.TextBlock
        $warning.Text = 'Adgangskoderne vises kun her. De skrives ikke til log, JSON eller handoff. Gem dem straks sikkert efter intern/kundeprocedure.'
        $warning.TextWrapping = 'Wrap'
        $warning.Margin = '0,0,0,10'
        [System.Windows.Controls.DockPanel]::SetDock($warning, 'Top')
        $panel.Children.Add($warning) | Out-Null
        $text = New-Object System.Windows.Controls.TextBox
        $text.IsReadOnly = $true
        $text.AcceptsReturn = $true
        $text.VerticalScrollBarVisibility = 'Auto'
        $text.FontFamily = 'Consolas'
        $text.Text = (($CreatedPasswords | ForEach-Object {
            '{0}: {1}' -f (Get-NetIPObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName'), (Get-NetIPObjectPropertyValue -InputObject $_ -Name 'Password')
        }) -join [Environment]::NewLine)
        $panel.Children.Add($text) | Out-Null
        $buttons = New-Object System.Windows.Controls.StackPanel
        $buttons.Orientation = 'Horizontal'
        $buttons.HorizontalAlignment = 'Right'
        $buttons.Margin = '0,10,0,0'
        [System.Windows.Controls.DockPanel]::SetDock($buttons, 'Bottom')
        $copy = New-Object System.Windows.Controls.Button
        $copy.Content = 'Kopiér alle'
        $copy.Width = 110
        $copy.Margin = '0,0,8,0'
        $copy.Add_Click({ [System.Windows.Clipboard]::SetText($text.Text) })
        $close = New-Object System.Windows.Controls.Button
        $close.Content = 'Luk'
        $close.Width = 90
        $close.Add_Click({ $window.Close() })
        $buttons.Children.Add($copy) | Out-Null
        $buttons.Children.Add($close) | Out-Null
        $panel.Children.Add($buttons) | Out-Null
        $window.Content = $panel
        $window.ShowDialog() | Out-Null
        $text.Text = ''
    })
    $sync.State.CreatedPasswords = @()
}
