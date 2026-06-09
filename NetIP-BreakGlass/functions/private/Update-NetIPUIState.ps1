function Update-NetIPUIState {
    [CmdletBinding()]
    param()

    if (-not $sync.Form) { return }
    $domain = [string]$sync.State.OnMicrosoftDomain
    if ($sync.WPFDomain) { $sync.WPFDomain.Text = $domain }
    if ($sync.WPFUpnPreview1 -and $domain) { $sync.WPFUpnPreview1.Text = "$(if($sync.WPFUserPrefix1){$sync.WPFUserPrefix1.Text})@$domain" }
    if ($sync.WPFUpnPreview2 -and $domain) { $sync.WPFUpnPreview2.Text = "$(if($sync.WPFUserPrefix2){$sync.WPFUserPrefix2.Text})@$domain" }
    if ($sync.WPFGraphStatus) { $sync.WPFGraphStatus.Text = if ($sync.State.GraphConnected) { 'Ja' } else { 'Nej' } }
    if ($sync.WPFGraphAccount) { $sync.WPFGraphAccount.Text = [string]$sync.State.GraphAccount }
    if ($sync.WPFTenantId) { $sync.WPFTenantId.Text = [string]$sync.State.TenantId }
    if ($sync.WPFTenantName) { $sync.WPFTenantName.Text = [string]$sync.State.TenantDisplayName }
    if ($sync.WPFOnMicrosoftDomain) { $sync.WPFOnMicrosoftDomain.Text = [string]$sync.State.OnMicrosoftDomain }
    if ($sync.WPFOutputFolder) { $sync.WPFOutputFolder.Text = [string]$sync.State.OutputFolder }
    if ($sync.WPFHandoffPath) { $sync.WPFHandoffPath.Text = [string]$sync.State.HandoffPath }
    $risk = [bool]$sync.WPFWelcomeRiskAccepted.IsChecked
    $sync.WPFStepConnect.IsEnabled = $risk
    $sync.WPFStepDiscovery.IsEnabled = $risk -and [bool]$sync.State.GraphConnected
    $sync.WPFStepConfig.IsEnabled = $risk -and [bool]$sync.State.GraphConnected
    $sync.WPFStepPlan.IsEnabled = $risk -and [bool]$sync.State.GraphConnected
    $sync.WPFStepApply.IsEnabled = $risk -and $null -ne $sync.State.Plan
    $sync.WPFStepHandoff.IsEnabled = $risk -and -not [string]::IsNullOrWhiteSpace([string]$sync.State.HandoffPath)
}
