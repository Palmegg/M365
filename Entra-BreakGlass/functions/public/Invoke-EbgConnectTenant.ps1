function Invoke-EbgConnectTenant {
    [CmdletBinding()]
    param()

    Invoke-EbgRunspace -ScriptBlock {
        if ($sync.App.Mock) {
            $sync.State.GraphConnected = $true
            $sync.State.GraphAccount = 'mock.consultant@contoso.onmicrosoft.com'
            Get-EbgTenantInfo | Out-Null
            Write-EbgStatus -Message 'Mock tenant er forbundet.'
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
        Connect-MgGraph -Scopes $scopes -ContextScope Process -NoWelcome -ErrorAction Stop | Out-Null
        $context = Get-MgContext
        $sync.State.GraphConnected = $true
        $sync.State.GraphAccount = [string]$context.Account
        $sync.State.GraphScopes = @($context.Scopes)
        Get-EbgTenantInfo | Out-Null
        Write-EbgStatus -Message 'Microsoft Graph er forbundet.'
    }
}