function Invoke-EbgConnectTenant {
    [CmdletBinding()]
    param()

    Invoke-EbgRunspace -ScriptBlock {
        if ($sync.App.Mock) {
            $sync.State.GraphConnected = $true
            $sync.State.GraphAccount = 'mock.consultant@contoso.onmicrosoft.com'
            Get-EbgTenantInfo | Out-Null
            Write-EbgStatus -Message 'Mock tenant er forbundet.'
            [void]$sync.Form.Dispatcher.Invoke([System.Action]{
                Update-EbgUIState | Out-Null
                if ($sync.WPFGraphStatus) { $sync.WPFGraphStatus.Text = if ([string]$sync.State.Language -eq 'en-US') { 'Yes' } else { 'Ja' } }
                if ($sync.WPFStepDiscovery) { $sync.WPFStepDiscovery.IsEnabled = $true }
                if ($sync.WPFNextStep -and [string]$sync.UI.CurrentStep -eq 'Connect') { $sync.WPFNextStep.IsEnabled = $true }
            })
            return
        }

        Write-EbgStatus -Busy -Message 'Forbinder til Microsoft Graph...'
        $scopes = @($sync.configs.graphScopes)
        $sync.State.GraphConnected = $false
        $sync.State.GraphAccount = ''
        $sync.State.TenantId = ''
        $sync.State.TenantDisplayName = ''
        $sync.State.OnMicrosoftDomain = ''
        $sync.State.GraphScopes = @()
        $sync.State.GraphAccessToken = ''
        $sync.State.GraphRefreshToken = ''
        $sync.State.GraphTokenExpires = $null
        $sync.State.GraphClientId = ''
        [void]$sync.Form.Dispatcher.Invoke([System.Action]{ Update-EbgUIState | Out-Null })
        Write-EbgStatus -Busy -Message 'Åbner browser-login. Log ind med tenant-kontoen...'
        $context = Connect-EbgGraphBrowser -Scopes $scopes
        $sync.State.GraphConnected = $true
        $sync.State.GraphAccount = [string]$context.Account
        $sync.State.TenantId = [string]$context.TenantId
        $sync.State.GraphScopes = @($context.Scopes)
        $sync.State.GraphAccessToken = [string]$context.AccessToken
        $sync.State.GraphRefreshToken = [string]$context.RefreshToken
        $sync.State.GraphTokenExpires = $context.ExpiresOn
        $sync.State.GraphClientId = [string]$context.ClientId
        Get-EbgTenantInfo | Out-Null
        Write-EbgStatus -Message 'Microsoft Graph er forbundet.'
        $isEnglish = ([string]$sync.State.Language -eq 'en-US')
        [void]$sync.Form.Dispatcher.Invoke([System.Action]{
            Update-EbgUIState | Out-Null
            if ($sync.WPFGraphStatus) { $sync.WPFGraphStatus.Text = if ($isEnglish) { 'Yes' } else { 'Ja' } }
            if ($sync.WPFGraphAccount) { $sync.WPFGraphAccount.Text = [string]$sync.State.GraphAccount }
            if ($sync.WPFTenantId) { $sync.WPFTenantId.Text = [string]$sync.State.TenantId }
            if ($sync.WPFTenantName) { $sync.WPFTenantName.Text = [string]$sync.State.TenantDisplayName }
            if ($sync.WPFOnMicrosoftDomain) { $sync.WPFOnMicrosoftDomain.Text = [string]$sync.State.OnMicrosoftDomain }
            if ($sync.WPFStepDiscovery) { $sync.WPFStepDiscovery.IsEnabled = $true }
            if ($sync.WPFNextStep -and [string]$sync.UI.CurrentStep -eq 'Connect') { $sync.WPFNextStep.IsEnabled = $true }
        })
    }
}
