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
        $module = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication | Select-Object -First 1
        if (-not $module) {
            $install = $sync.Form.Dispatcher.Invoke([func[object]]{
                [System.Windows.MessageBox]::Show('Microsoft.Graph.Authentication mangler. Vil du installere modulet for CurrentUser fra PSGallery?', $sync.App.Name, 'YesNo', 'Question')
            })
            if ($install -ne 'Yes') {
                throw 'Microsoft Graph modulet mangler, og installation blev ikke godkendt.'
            }
            Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
        }

        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        $scopes = @($sync.configs.graphScopes)

        try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Set-MgGraphOption -DisableLoginByWAM $true -ErrorAction SilentlyContinue | Out-Null } catch {}

        $sync.State.GraphConnected = $false
        $sync.State.GraphAccount = ''
        $sync.State.TenantId = ''
        $sync.State.TenantDisplayName = ''
        $sync.State.OnMicrosoftDomain = ''
        $sync.State.GraphScopes = @()
        [void]$sync.Form.Dispatcher.Invoke([System.Action]{ Update-EbgUIState | Out-Null })

        Write-EbgStatus -Busy -Message 'Åbner Microsoft Graph-login. Vælg tenant-konto i Microsoft loginvinduet...'
        Connect-MgGraph -Scopes $scopes -ContextScope Process -NoWelcome -ErrorAction Stop | Out-Null

        $context = Get-MgContext -ErrorAction Stop
        if (-not $context -or [string]::IsNullOrWhiteSpace([string]$context.Account)) {
            throw 'Microsoft Graph login returnerede ingen aktiv konto.'
        }

        $sync.State.GraphConnected = $true
        $sync.State.GraphAccount = [string]$context.Account
        $sync.State.GraphScopes = @($context.Scopes)
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
