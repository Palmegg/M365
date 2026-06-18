function Ensure-EbgGraphContext {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) { return }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $context = $null
    try {
        $context = Get-MgContext -ErrorAction Stop
    }
    catch {
        $context = $null
    }

    if (-not $context -or [string]::IsNullOrWhiteSpace([string]$context.Account)) {
        $scopes = @($sync.State.GraphScopes)
        if ($scopes.Count -eq 0) {
            $scopes = @($sync.configs.graphScopes)
        }

        Write-EbgLog -Message 'Graph context mangler i worker-runspace. Forsøger at genbruge aktuel Graph PowerShell login-session...'
        Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop | Out-Null
        $context = Get-MgContext -ErrorAction Stop
    }

    if (-not $context -or [string]::IsNullOrWhiteSpace([string]$context.Account)) {
        throw 'Microsoft Graph context er ikke aktiv i denne PowerShell runspace. Gå tilbage til Forbind og log på igen.'
    }

    $sync.State.GraphConnected = $true
    $sync.State.GraphAccount = [string]$context.Account
    $sync.State.GraphScopes = @($context.Scopes)
}
