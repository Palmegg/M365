function Invoke-EbgConnectTenant {
    [CmdletBinding()]
    param()

    if ($sync.UI.ProcessRunning) {
        [System.Windows.MessageBox]::Show('Der kører allerede en opgave. Vent til den er færdig.', $sync.App.Name, 'OK', 'Information') | Out-Null
        return
    }

    $sync.UI.ProcessRunning = $true
    if ($sync.WPFConnectTenant) { $sync.WPFConnectTenant.IsEnabled = $false }

    try {
        if ($sync.App.Mock) {
            $sync.State.GraphConnected = $true
            $sync.State.GraphAccount = 'mock.consultant@contoso.onmicrosoft.com'
            Get-EbgTenantInfo | Out-Null
            Write-EbgStatus -Message 'Mock tenant er forbundet.'
            Update-EbgUIState | Out-Null
            return
        }

        Write-EbgStatus -Busy -Message 'Forbinder til Microsoft Graph...'
        [System.Windows.Forms.Application]::DoEvents()

        $module = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication | Select-Object -First 1
        if (-not $module) {
            $install = [System.Windows.MessageBox]::Show('Microsoft.Graph.Authentication mangler. Vil du installere modulet for CurrentUser fra PSGallery?', $sync.App.Name, 'YesNo', 'Question')
            if ($install -ne 'Yes') {
                throw 'Microsoft Graph modulet mangler, og installation blev ikke godkendt.'
            }
            Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
        }

        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        $scopes = @($sync.configs.graphScopes)

        try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
        Clear-EbgGraphLoginCache
        try { Set-MgGraphOption -DisableLoginByWAM $true -ErrorAction SilentlyContinue | Out-Null } catch {}

        $sync.State.GraphConnected = $false
        $sync.State.GraphAccount = ''
        $sync.State.TenantId = ''
        $sync.State.TenantDisplayName = ''
        $sync.State.OnMicrosoftDomain = ''
        $sync.State.GraphScopes = @()
        Update-EbgUIState | Out-Null
        [System.Windows.Forms.Application]::DoEvents()

        Write-EbgStatus -Busy -Message 'Åbner frisk Microsoft Graph-login. Vælg tenant-konto i Microsoft loginvinduet...'
        Write-Host 'Når login er gennemført, fokuserer BreakGlassConfigurator automatisk igen.' -ForegroundColor Green
        [System.Windows.Forms.Application]::DoEvents()

        if ($sync.Form) {
            $sync.UI.PreGraphLoginWindowState = [string]$sync.Form.WindowState
            $sync.UI.GraphLoginMinimizedWindow = $true
            $sync.Form.Topmost = $false
            $sync.Form.WindowState = 'Minimized'
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 300
        }

        Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop | Out-Null

        $context = Get-MgContext -ErrorAction Stop
        if (-not $context -or [string]::IsNullOrWhiteSpace([string]$context.Account)) {
            throw 'Microsoft Graph login returnerede ingen aktiv konto.'
        }

        $sync.State.GraphConnected = $true
        $sync.State.GraphAccount = [string]$context.Account
        $sync.State.GraphScopes = @($context.Scopes)
        Get-EbgTenantInfo | Out-Null
        Write-EbgStatus -Message 'Microsoft Graph er forbundet.'
        Write-Host 'Login OK. BreakGlassConfigurator fokuseres nu automatisk.' -ForegroundColor Green
        Update-EbgUIState | Out-Null
        Set-EbgMainWindowForeground
    }
    catch {
        $message = ConvertTo-EbgRedactedError -ErrorRecord $_
        Write-EbgLog -Level ERROR -Message $message
        Write-EbgStatus -Message 'Microsoft Graph login fejlede.'
        [System.Windows.MessageBox]::Show($message, $sync.App.Name, 'OK', 'Error') | Out-Null
    }
    finally {
        $sync.UI.ProcessRunning = $false
        if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $false }
        if ($sync.WPFConnectTenant) { $sync.WPFConnectTenant.IsEnabled = $true }
        Update-EbgUIState | Out-Null
        if ($sync.State.GraphConnected -or $sync.UI.GraphLoginMinimizedWindow) { Set-EbgMainWindowForeground }
    }
}
