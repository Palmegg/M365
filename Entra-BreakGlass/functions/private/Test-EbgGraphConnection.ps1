function Test-EbgGraphConnection {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) { return $true }
    try {
        return -not [string]::IsNullOrWhiteSpace([string](Get-EbgGraphAccessToken))
    }
    catch {
        return $false
    }
}
