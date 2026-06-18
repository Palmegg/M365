function Initialize-EbgWPFUI {
    [CmdletBinding()]
    param()

    $settings = $sync.configs.appsettings
    $defaults = $sync.configs.defaults
    $scopes = @($sync.configs.graphScopes)
    if ($settings) {
        $sync.App.Name = [string]$settings.name
        $sync.App.Version = [string]$settings.version
    }
    $sync.Form.Title = "$($sync.App.Name) v$($sync.App.Version)"
    $sync.WPFVersionBadge.Text = "v$($sync.App.Version)"
    $sync.WPFGraphScopes.Text = ($scopes -join [Environment]::NewLine)
    $sync.WPFDisplayName1.Text = [string]$defaults.account1DisplayName
    $sync.WPFUserPrefix1.Text = [string]$defaults.account1Prefix
    $sync.WPFDisplayName2.Text = [string]$defaults.account2DisplayName
    $sync.WPFUserPrefix2.Text = [string]$defaults.account2Prefix
    $sync.WPFGroupName.Text = [string]$settings.groupName
    $sync.WPFGroupDescription.Text = [string]$settings.groupDescription
    $sync.WPFAuthenticationStrengthName.Text = [string]$settings.authenticationStrengthName
    $sync.WPFBreakGlassCAPolicyName.Text = [string]$settings.breakGlassCAPolicyName
    $sync.WPFCreateUsers.IsChecked = [bool]$defaults.createUsers
    $sync.WPFCreateGroup.IsChecked = [bool]$defaults.createGroup
    $sync.WPFAddUsersToGroup.IsChecked = [bool]$defaults.addUsersToGroup
    $sync.WPFDisableAdminSSPR.IsChecked = [bool]$defaults.disableAdminSSPR
    $sync.WPFPatchCAPolicies.IsChecked = [bool]$defaults.patchCAPolicies
    if ($sync.WPFCreateAuthenticationStrength) { $sync.WPFCreateAuthenticationStrength.IsChecked = [bool]$defaults.createAuthenticationStrength }
    if ($sync.WPFCreateBreakGlassCAPolicy) { $sync.WPFCreateBreakGlassCAPolicy.IsChecked = [bool]$defaults.createBreakGlassCAPolicy }
    if ($sync.WPFEnableBreakGlassCAPolicy) { $sync.WPFEnableBreakGlassCAPolicy.IsChecked = [bool]$defaults.enableBreakGlassCAPolicy }
    if ($sync.WPFLanguageSelector) { $sync.WPFLanguageSelector.SelectedIndex = 0 }
    Set-EbgNeutralAccountNamePair -Random
    Set-EbgLanguage -Language $sync.State.Language

    if ($sync.App.Mock) {
        $sync.State.GraphConnected = $true
        $sync.State.GraphAccount = 'mock.consultant@contoso.onmicrosoft.com'
        Get-EbgTenantInfo | Out-Null
        Write-EbgStatus -Message 'Mock mode er aktiv. Der kaldes ikke Microsoft Graph.'
    }
    else {
        Write-EbgStatus -Message 'Klar'
    }
    Invoke-EbgWPFButton -Name 'WPFStepWelcome'
    Update-EbgUIState
}