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
        $workerRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("EbgGraphConnect-{0}" -f ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $workerRoot -Force | Out-Null
        $workerScript = Join-Path $workerRoot 'ConnectGraphWorker.ps1'
        $resultPath = Join-Path $workerRoot 'result.json'
        $stdoutPath = Join-Path $workerRoot 'stdout.log'
        $stderrPath = Join-Path $workerRoot 'stderr.log'
        $scopeJson = ConvertTo-Json -InputObject $scopes -Compress
        $workerCode = @"
`$ErrorActionPreference = 'Stop'
`$result = [ordered]@{
    Success = `$false
    Account = ''
    TenantId = ''
    Scopes = @()
    Error = ''
}
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
    `$scopes = '$scopeJson' | ConvertFrom-Json
    Connect-MgGraph -Scopes `$scopes -ContextScope CurrentUser -NoWelcome -ErrorAction Stop | Out-Null
    `$context = Get-MgContext -ErrorAction Stop
    if (-not `$context -or [string]::IsNullOrWhiteSpace([string]`$context.Account)) {
        throw 'Microsoft Graph login returned no account context.'
    }
    `$result.Success = `$true
    `$result.Account = [string]`$context.Account
    `$result.TenantId = [string]`$context.TenantId
    `$result.Scopes = @(`$context.Scopes)
}
catch {
    `$result.Error = [string]`$_.Exception.Message
}
finally {
    `$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath '$($resultPath.Replace("'","''"))' -Encoding UTF8
}
"@
        Set-Content -LiteralPath $workerScript -Value $workerCode -Encoding UTF8
        $pwshPath = Join-Path $PSHOME 'pwsh.exe'
        if (-not (Test-Path -LiteralPath $pwshPath)) {
            $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
        }
        Write-EbgStatus -Busy -Message 'Åbner Microsoft Graph-login i browseren. Gennemfør loginvinduet...'
        $process = Start-Process -FilePath $pwshPath -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $workerScript
        ) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
        $connectStarted = Get-Date
        $lastStatus = Get-Date
        while (-not $process.HasExited) {
            $elapsed = (Get-Date) - $connectStarted
            if ($elapsed.TotalMinutes -ge 5) {
                try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
                throw 'Microsoft Graph login timed out efter 5 minutter. Prøv igen, og tjek om Microsoft-loginvinduet ligger bag andre vinduer eller er blokeret af browseren.'
            }
            if (((Get-Date) - $lastStatus).TotalSeconds -ge 20) {
                Write-EbgStatus -Busy -Message 'Venter på Microsoft Graph-login. Tjek browseren eller loginvinduet...'
                $lastStatus = Get-Date
            }
            Start-Sleep -Milliseconds 300
        }
        if ($process.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $resultPath)) {
            $workerError = if (Test-Path -LiteralPath $stderrPath) { (Get-Content -LiteralPath $stderrPath -Raw) } else { '' }
            throw "Microsoft Graph login-worker fejlede med exit code $($process.ExitCode). $workerError"
        }
        if (-not (Test-Path -LiteralPath $resultPath)) {
            throw 'Microsoft Graph login-worker returnerede ikke et resultat.'
        }
        $workerResult = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        if (-not [bool]$workerResult.Success) {
            throw "Microsoft Graph login fejlede: $($workerResult.Error)"
        }
        Connect-MgGraph -ContextScope CurrentUser -NoWelcome -ErrorAction Stop | Out-Null
        $context = Get-MgContext
        if (-not $context -or [string]::IsNullOrWhiteSpace([string]$context.Account)) {
            throw 'Microsoft Graph login lykkedes, men GUI-processen kunne ikke genbruge Graph-context. Prøv at lukke appen og starte igen.'
        }
        $sync.State.GraphConnected = $true
        $sync.State.GraphAccount = [string]$context.Account
        $sync.State.GraphScopes = @($context.Scopes)
        Get-EbgTenantInfo | Out-Null
        Write-EbgStatus -Message 'Microsoft Graph er forbundet.'
        Remove-Item -LiteralPath $workerRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
