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
        $sync.State.GraphConnected = $false
        $sync.State.GraphAccount = ''
        $sync.State.TenantId = ''
        $sync.State.TenantDisplayName = ''
        $sync.State.OnMicrosoftDomain = ''
        $sync.State.GraphScopes = @()
        [void]$sync.Form.Dispatcher.Invoke([System.Action]{ Update-EbgUIState | Out-Null })
        Write-EbgStatus -Busy -Message 'Åbner separat PowerShell-vindue til Microsoft Graph-login...'

        $workerRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("EbgGraphLogin-{0}" -f ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $workerRoot -Force | Out-Null
        $workerScript = Join-Path $workerRoot 'Connect-MgGraph-Login.ps1'
        $resultPath = Join-Path $workerRoot 'result.json'
        $scopeLiteral = (($scopes | ForEach-Object { "'$($_.Replace("'", "''"))'" }) -join ', ')
        $workerCode = @"
`$ErrorActionPreference = 'Stop'
`$resultPath = '$($resultPath.Replace("'", "''"))'
`$result = [ordered]@{
    Success = `$false
    Account = ''
    TenantId = ''
    Scopes = @()
    Error = ''
}
try {
    `$host.UI.RawUI.WindowTitle = 'Entra Break Glass Configurator - Microsoft Graph login'
    Write-Host ''
    Write-Host 'Entra Break Glass Configurator - Microsoft Graph login' -ForegroundColor Cyan
    Write-Host 'Dette vindue bruges kun til Microsoft Graph login.' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Log ind i Microsoft loginvinduet. Når login er gennemført, kan du lukke dette PowerShell-vindue for at fortsætte i WPF.' -ForegroundColor Yellow
    Write-Host ''
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Set-MgGraphOption -DisableLoginByWAM `$true -ErrorAction SilentlyContinue | Out-Null } catch {}
    `$scopes = @($scopeLiteral)
    Connect-MgGraph -Scopes `$scopes -ContextScope CurrentUser -NoWelcome -ErrorAction Stop | Out-Null
    `$context = Get-MgContext -ErrorAction Stop
    if (-not `$context -or [string]::IsNullOrWhiteSpace([string]`$context.Account)) {
        throw 'Microsoft Graph login returnerede ingen aktiv konto.'
    }
    `$result.Success = `$true
    `$result.Account = [string]`$context.Account
    `$result.TenantId = [string]`$context.TenantId
    `$result.Scopes = @(`$context.Scopes)
    Write-Host ''
    Write-Host "Login OK: `$(`$context.Account)" -ForegroundColor Green
    Write-Host 'Luk dette PowerShell-vindue for at fortsætte i WPF.' -ForegroundColor Green
}
catch {
    `$result.Error = [string]`$_.Exception.Message
    Write-Host ''
    Write-Host "Login fejlede: `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Luk dette PowerShell-vindue for at vende tilbage til WPF.' -ForegroundColor Yellow
}
finally {
    `$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath `$resultPath -Encoding UTF8
    while (`$true) { Start-Sleep -Seconds 1 }
}
"@
        Set-Content -LiteralPath $workerScript -Value $workerCode -Encoding UTF8
        $pwshPath = Join-Path $PSHOME 'pwsh.exe'
        if (-not (Test-Path -LiteralPath $pwshPath)) {
            $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
        }
        $process = Start-Process -FilePath $pwshPath -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $workerScript
        ) -WindowStyle Normal -PassThru
        Write-EbgStatus -Busy -Message 'Afventer Microsoft Graph-login. Luk login-PowerShell-vinduet når der står Login OK...'
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 300
        }
        if (-not (Test-Path -LiteralPath $resultPath)) {
            throw 'Login-vinduet blev lukket før Microsoft Graph returnerede et resultat.'
        }
        $workerResult = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        if (-not [bool]$workerResult.Success) {
            throw "Microsoft Graph login fejlede: $($workerResult.Error)"
        }

        try { Set-MgGraphOption -DisableLoginByWAM $true -ErrorAction SilentlyContinue | Out-Null } catch {}
        Connect-MgGraph -ContextScope CurrentUser -NoWelcome -ErrorAction Stop | Out-Null
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
        Remove-Item -LiteralPath $workerRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
