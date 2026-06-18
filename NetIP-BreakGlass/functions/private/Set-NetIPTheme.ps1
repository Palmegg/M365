function Set-NetIPTheme {
    [CmdletBinding()]
    param([ValidateSet('Dark','Light')][string] $Theme = 'Dark')

    if (-not $sync.Form) { return }
    if (-not $sync.Form.Dispatcher.CheckAccess()) {
        $sync.Form.Dispatcher.Invoke([System.Action]{ Set-NetIPTheme -Theme $Theme })
        return
    }

    $sync.State.Theme = $Theme

    $palette = if ($Theme -eq 'Light') {
        @{
            AppBackground   = '#F5F7FB'
            PanelBackground = '#FFFFFF'
            PanelRaised     = '#F8FAFC'
            TextPrimary     = '#0F172A'
            TextSecondary   = '#334155'
            TextMuted       = '#64748B'
            BorderStrong    = '#CBD5E1'
            BorderSoft      = '#D6DEE8'
            Accent          = '#2563EB'
            AccentSoft      = '#E0ECFF'
            Header          = '#FFFFFF'
            HeaderBorder    = '#D6DEE8'
            Navigation      = '#FFFFFF'
            Status          = '#FFFFFF'
            Version         = '#EEF4FF'
            LogBackground   = '#FFFFFF'
            ProgressBack    = '#E2E8F0'
        }
    }
    else {
        @{
            AppBackground   = '#12101C'
            PanelBackground = '#171522'
            PanelRaised     = '#221F33'
            TextPrimary     = '#F8FAFC'
            TextSecondary   = '#CBD5E1'
            TextMuted       = '#94A3B8'
            BorderStrong    = '#94A3B8'
            BorderSoft      = '#3B3657'
            Accent          = '#38BDF8'
            AccentSoft      = '#0F3040'
            Header          = '#161423'
            HeaderBorder    = '#2F2B45'
            Navigation      = '#1D1A2E'
            Status          = '#161423'
            Version         = '#252138'
            LogBackground   = '#0F1115'
            ProgressBack    = '#1F2937'
        }
    }

    function New-NetIPThemeBrush([string] $Color) {
        return [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    }

    function Set-NetIPThemeBrushResource([string] $Key, [string] $Color) {
        $sync.Form.Resources[$Key] = New-NetIPThemeBrush $Color
    }

    foreach ($key in @('AppBackground','PanelBackground','PanelRaised','TextPrimary','TextSecondary','TextMuted','BorderStrong','BorderSoft','Accent','AccentSoft')) {
        Set-NetIPThemeBrushResource -Key $key -Color $palette[$key]
    }

    $backgroundBrush = New-NetIPThemeBrush $palette.AppBackground
    $headerBrush = New-NetIPThemeBrush $palette.Header
    $headerBorderBrush = New-NetIPThemeBrush $palette.HeaderBorder
    $navigationBrush = New-NetIPThemeBrush $palette.Navigation
    $statusBrush = New-NetIPThemeBrush $palette.Status
    $versionBrush = New-NetIPThemeBrush $palette.Version
    $borderBrush = New-NetIPThemeBrush $palette.BorderSoft
    $logBrush = New-NetIPThemeBrush $palette.LogBackground
    $progressBackBrush = New-NetIPThemeBrush $palette.ProgressBack
    $textBrush = $sync.Form.Resources['TextPrimary']
    $secondaryTextBrush = $sync.Form.Resources['TextSecondary']
    $raisedBrush = $sync.Form.Resources['PanelRaised']
    $accentSoftBrush = $sync.Form.Resources['AccentSoft']

    function Set-NetIPObjectTheme([AllowNull()] $Object) {
        if ($null -eq $Object -or -not ($Object -is [System.Windows.DependencyObject])) { return }

        if ($Object -is [System.Windows.Controls.TextBlock]) {
            $Object.Foreground = $textBrush
        }
        elseif ($Object -is [System.Windows.Controls.TextBox]) {
            $Object.Background = $logBrush
            $Object.Foreground = $textBrush
            $Object.BorderBrush = $borderBrush
            $Object.CaretBrush = $textBrush
        }
        elseif ($Object -is [System.Windows.Controls.RichTextBox]) {
            $Object.Background = $logBrush
            $Object.Foreground = $textBrush
            $Object.BorderBrush = $borderBrush
        }
        elseif ($Object -is [System.Windows.Controls.ComboBox]) {
            $Object.Background = $raisedBrush
            $Object.Foreground = $textBrush
            $Object.BorderBrush = $borderBrush
        }
        elseif ($Object -is [System.Windows.Controls.CheckBox]) {
            $Object.Foreground = $textBrush
        }
        elseif ($Object -is [System.Windows.Controls.Primitives.ToggleButton]) {
            $Object.Background = $raisedBrush
            $Object.Foreground = $textBrush
            $Object.BorderBrush = $borderBrush
        }
        elseif ($Object -is [System.Windows.Controls.Button]) {
            $Object.Background = $raisedBrush
            $Object.Foreground = $textBrush
            $Object.BorderBrush = $borderBrush
        }

        foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Object)) {
            Set-NetIPObjectTheme $child
        }
        try {
            $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Object)
            for ($i = 0; $i -lt $count; $i++) {
                Set-NetIPObjectTheme ([System.Windows.Media.VisualTreeHelper]::GetChild($Object, $i))
            }
        }
        catch {
            return
        }
    }

    $sync.Form.Background = $backgroundBrush
    Set-NetIPObjectTheme $sync.Form

    if ($sync.WPFRootGrid) { $sync.WPFRootGrid.Background = $backgroundBrush }
    if ($sync.WPFHeader) {
        $sync.WPFHeader.Background = $headerBrush
        $sync.WPFHeader.BorderBrush = $headerBorderBrush
    }
    if ($sync.WPFNavigationBar) {
        $sync.WPFNavigationBar.Background = $navigationBrush
        $sync.WPFNavigationBar.BorderBrush = $borderBrush
    }
    if ($sync.WPFStatusBar) {
        $sync.WPFStatusBar.Background = $statusBrush
        $sync.WPFStatusBar.BorderBrush = $headerBorderBrush
    }
    if ($sync.WPFVersionBadge -and $sync.WPFVersionBadge.Parent -is [System.Windows.Controls.Border]) {
        $sync.WPFVersionBadge.Parent.Background = $versionBrush
        $sync.WPFVersionBadge.Parent.BorderBrush = $borderBrush
    }
    if ($sync.WPFStatusText) { $sync.WPFStatusText.Foreground = $secondaryTextBrush }
    if ($sync.WPFCurrentStepText) { $sync.WPFCurrentStepText.Foreground = $secondaryTextBrush }
    if ($sync.WPFAppSubtitle) { $sync.WPFAppSubtitle.Foreground = $secondaryTextBrush }
    if ($sync.WPFProgressBar) { $sync.WPFProgressBar.Background = $progressBackBrush }
    if ($sync.WPFDiscoveryList) {
        $sync.WPFDiscoveryList.Background = $logBrush
        $sync.WPFDiscoveryList.Foreground = $textBrush
        $sync.WPFDiscoveryList.BorderBrush = $borderBrush
    }
    if ($sync.WPFExecutionLog) {
        $sync.WPFExecutionLog.Background = $logBrush
        $sync.WPFExecutionLog.Foreground = $textBrush
        $sync.WPFExecutionLog.BorderBrush = $borderBrush
    }
    if ($sync.WPFPlanText) {
        $sync.WPFPlanText.Background = $logBrush
        $sync.WPFPlanText.Foreground = $textBrush
        $sync.WPFPlanText.BorderBrush = $borderBrush
    }
    if ($sync.WPFGraphScopes) {
        $sync.WPFGraphScopes.Background = $logBrush
        $sync.WPFGraphScopes.Foreground = $textBrush
        $sync.WPFGraphScopes.BorderBrush = $borderBrush
    }

    if ($sync.WPFThemeToggle) {
        $sync.WPFThemeToggle.IsChecked = ($Theme -eq 'Light')
        $sync.WPFThemeToggle.Background = $accentSoftBrush
        $sync.WPFThemeToggle.BorderBrush = $sync.Form.Resources['Accent']
        if ([string]$sync.State.Language -eq 'en-US') {
            $sync.WPFThemeToggle.Content = if ($Theme -eq 'Light') { 'Light mode' } else { 'Dark mode' }
        }
        else {
            $sync.WPFThemeToggle.Content = if ($Theme -eq 'Light') { 'Lys tilstand' } else { 'Mørk tilstand' }
        }
    }

    Update-NetIPUIState
}
