function Get-NetIPAuthorizationPolicy {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) {
        return [pscustomobject]@{
            id = 'authorizationPolicy'
            allowedToUseSSPR = $true
        }
    }

    Write-NetIPLog -Message 'Henter authorization policy for administrator-SSPR...'
    $policy = Invoke-NetIPGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy?$select=id,allowedToUseSSPR'
    if (-not $policy) {
        throw 'Kunne ikke hente authorization policy via Microsoft Graph.'
    }
    return $policy
}
