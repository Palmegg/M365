function Invoke-EbgConnectTenant {
    [CmdletBinding()]
    param()

    if ($sync.UI.ProcessRunning) {
        [System.Windows.MessageBox]::Show('Der kører allerede en opgave. Vent til den er færdig.', $sync.App.Name, 'OK', 'Information') | Out-Null
        return
    }

    if ($sync.App.Mock) {
        $sync.State.GraphConnected = $true
        $sync.State.GraphAccount = 'mock.consultant@contoso.onmicrosoft.com'
        Get-EbgTenantInfo | Out-Null
        Write-EbgStatus -Message 'Mock tenant er forbundet.'
        Update-EbgUIState | Out-Null
        if ([string]$sync.State.StartMode -eq 'Phase2') {
            Invoke-EbgWPFButton -Name 'WPFStepPhase2'
        }
        return
    }

    $module = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication | Select-Object -First 1
    if (-not $module) {
        $install = [System.Windows.MessageBox]::Show('Microsoft.Graph.Authentication mangler. Vil du installere modulet for CurrentUser fra PSGallery?', $sync.App.Name, 'YesNo', 'Question')
        if ($install -ne 'Yes') {
            Write-EbgStatus -Message 'Microsoft Graph modulet mangler, og installation blev ikke godkendt.'
            return
        }
    }

    Invoke-EbgRunspace -ArgumentList @([bool](-not $module)) -ScriptBlock {
        param([bool] $installModule)

        if ($installModule) {
            Write-EbgStatus -Busy -Message 'Installerer Microsoft.Graph.Authentication for CurrentUser...'
            Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
        }

        Write-EbgStatus -Busy -Message 'Forbinder til Microsoft Graph...'
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

        Invoke-EbgUIThread -ScriptBlock {
            Update-EbgUIState | Out-Null
            if ($sync.Form) {
                $sync.UI.PreGraphLoginWindowState = [string]$sync.Form.WindowState
                $sync.UI.GraphLoginMinimizedWindow = $true
                $sync.Form.Topmost = $false
                $sync.Form.WindowState = 'Minimized'
            }
        } -Wait

        Write-EbgStatus -Busy -Message 'Åbner frisk Microsoft Graph-login. Vælg tenant-konto i Microsoft loginvinduet...'
        Write-Host 'Når login er gennemført, fokuserer BreakGlassConfigurator automatisk igen.' -ForegroundColor Green

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

        Invoke-EbgUIThread -ScriptBlock {
            Update-EbgUIState | Out-Null
            if ([string]$sync.State.StartMode -eq 'Phase2') {
                Invoke-EbgWPFButton -Name 'WPFStepPhase2'
            }
            Set-EbgMainWindowForeground
        } -Wait
    }
}
