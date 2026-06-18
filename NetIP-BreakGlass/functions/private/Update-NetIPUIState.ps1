function Update-NetIPUIState {
    [CmdletBinding()]
    param()

    if (-not $sync.Form) { return }
    if (-not $sync.Form.Dispatcher.CheckAccess()) {
        [void]$sync.Form.Dispatcher.Invoke([System.Action]{ Update-NetIPUIState | Out-Null })
        return
    }

    $domain = [string]$sync.State.OnMicrosoftDomain
    if ($sync.WPFDomain) { $sync.WPFDomain.Text = $domain }
    if ($sync.WPFUpnPreview1 -and $domain) { $sync.WPFUpnPreview1.Text = "$(if($sync.WPFUserPrefix1){$sync.WPFUserPrefix1.Text})@$domain" }
    if ($sync.WPFUpnPreview2 -and $domain) { $sync.WPFUpnPreview2.Text = "$(if($sync.WPFUserPrefix2){$sync.WPFUserPrefix2.Text})@$domain" }
    if ($sync.WPFGraphStatus) {
        $sync.WPFGraphStatus.Text = if ($sync.State.GraphConnected) {
            if ($sync.State.Language -eq 'en-US') { 'Yes' } else { 'Ja' }
        }
        else {
            if ($sync.State.Language -eq 'en-US') { 'No' } else { 'Nej' }
        }
    }
    if ($sync.WPFGraphAccount) { $sync.WPFGraphAccount.Text = [string]$sync.State.GraphAccount }
    if ($sync.WPFTenantId) { $sync.WPFTenantId.Text = [string]$sync.State.TenantId }
    if ($sync.WPFTenantName) { $sync.WPFTenantName.Text = [string]$sync.State.TenantDisplayName }
    if ($sync.WPFOnMicrosoftDomain) { $sync.WPFOnMicrosoftDomain.Text = [string]$sync.State.OnMicrosoftDomain }
    if ($sync.WPFOutputFolder) { $sync.WPFOutputFolder.Text = [string]$sync.State.OutputFolder }
    if ($sync.WPFHandoffPath) { $sync.WPFHandoffPath.Text = [string]$sync.State.HandoffPath }
    $risk = [bool]$sync.WPFWelcomeRiskAccepted.IsChecked
    $hasGraph = [bool]$sync.State.GraphConnected
    $hasDiscovery = $null -ne $sync.State.Discovery
    $hasVisitedConfig = [bool]$sync.UI.ConfigVisited
    $hasPlan = $null -ne $sync.State.Plan
    $hasPhase1 = $null -ne $sync.State.Phase1Result
    $hasHandoff = -not [string]::IsNullOrWhiteSpace([string]$sync.State.HandoffPath)

    $sync.WPFStepWelcome.IsEnabled = $true
    $sync.WPFStepConnect.IsEnabled = $risk
    $sync.WPFStepDiscovery.IsEnabled = $risk -and $hasGraph
    $sync.WPFStepConfig.IsEnabled = $risk -and $hasGraph -and $hasDiscovery
    $sync.WPFStepPlan.IsEnabled = $risk -and $hasGraph -and $hasDiscovery -and $hasVisitedConfig
    $sync.WPFStepApply.IsEnabled = $risk -and $hasGraph -and $hasPlan
    $sync.WPFStepManualFido.IsEnabled = $risk -and $hasPhase1
    $sync.WPFStepPhase2.IsEnabled = $risk -and $hasGraph -and $hasPhase1
    $sync.WPFStepHandoff.IsEnabled = $risk -and $hasHandoff

    $stepMap = @{
        Welcome = 'WPFStepWelcome'
        Connect = 'WPFStepConnect'
        Discovery = 'WPFStepDiscovery'
        Config = 'WPFStepConfig'
        Plan = 'WPFStepPlan'
        Apply = 'WPFStepApply'
        ManualFido = 'WPFStepManualFido'
        Phase2 = 'WPFStepPhase2'
        Handoff = 'WPFStepHandoff'
    }
    $activeBrush = $sync.Form.Resources['AccentSoft']
    $inactiveBrush = $sync.Form.Resources['PanelRaised']
    $activeBorderBrush = $sync.Form.Resources['Accent']
    $inactiveBorderBrush = $sync.Form.Resources['BorderSoft']
    foreach ($entry in $stepMap.GetEnumerator()) {
        $button = $sync[$entry.Value]
        if (-not $button) { continue }
        if ([string]$sync.UI.CurrentStep -eq [string]$entry.Key) {
            $button.Background = $activeBrush
            $button.BorderBrush = $activeBorderBrush
        }
        else {
            $button.Background = $inactiveBrush
            $button.BorderBrush = $inactiveBorderBrush
        }
    }

    $steps = @('Welcome','Connect','Discovery','Config','Plan','Apply','ManualFido','Phase2','Handoff')
    $titles = @{
        Welcome = 'Velkommen'
        Connect = 'Forbind'
        Discovery = 'Discovery'
        Config = 'Konfiguration'
        Plan = 'Plan'
        Apply = 'Phase 1a'
        ManualFido = 'Manuel FIDO2'
        Phase2 = 'Phase 2'
        Handoff = 'Handoff'
    }
    $current = [string]$sync.UI.CurrentStep
    $index = [array]::IndexOf($steps, $current)
    if ($index -lt 0) { $index = 0; $current = 'Welcome' }

    if ($sync.WPFCurrentStepText) {
        $sync.WPFCurrentStepText.Text = "Step $($index + 1) af $($steps.Count): $($titles[$current])"
    }

    if ($sync.WPFBackStep) {
        $sync.WPFBackStep.Visibility = if ($index -eq 0) { 'Hidden' } else { 'Visible' }
        $sync.WPFBackStep.Content = if ($index -gt 0) { "Tilbage til $($titles[$steps[$index - 1]])" } else { 'Tilbage' }
    }

    if ($sync.WPFNextStep) {
        if ($index -ge ($steps.Count - 1)) {
            $sync.WPFNextStep.Visibility = 'Hidden'
            $sync.WPFNextStep.IsEnabled = $false
            $sync.WPFNextStep.Content = 'Videre'
        }
        else {
            $nextStep = $steps[$index + 1]
            $nextButtonName = $stepMap[$nextStep]
            $sync.WPFNextStep.Visibility = 'Visible'
            $sync.WPFNextStep.IsEnabled = if ($sync[$nextButtonName]) { [bool]$sync[$nextButtonName].IsEnabled } else { $false }
            $sync.WPFNextStep.Content = "Videre til $($titles[$nextStep])"
        }
    }
}
