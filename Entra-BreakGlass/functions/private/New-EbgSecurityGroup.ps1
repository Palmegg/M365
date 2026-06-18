function New-EbgSecurityGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][string] $Description
    )

    if ($sync.App.Mock) {
        return [pscustomobject]@{ id = 'mock-ca-exclude-group'; displayName = $DisplayName; description = $Description; mailEnabled = $false; securityEnabled = $true; groupTypes = @(); EnsureStatus = 'Created' }
    }
    $body = @{
        displayName     = $DisplayName
        description     = $Description
        mailEnabled     = $false
        mailNickname    = 'CABreakGlassExclude'
        securityEnabled = $true
        groupTypes      = @()
    }
    Invoke-EbgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/groups' -Body $body | Out-Null
    return Get-EbgGroupByDisplayName -DisplayName $DisplayName
}