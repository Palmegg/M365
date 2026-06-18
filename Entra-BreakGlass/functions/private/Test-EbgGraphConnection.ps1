function Test-EbgGraphConnection {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) { return $true }
    try {
        $context = Get-MgContext -ErrorAction Stop
        return ($null -ne $context -and -not [string]::IsNullOrWhiteSpace([string]$context.Account))
    }
    catch {
        return $false
    }
}