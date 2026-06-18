function Get-EbgGraphAccessToken {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace([string]$sync.State.GraphAccessToken)) {
        throw 'Microsoft Graph er ikke forbundet. Forbind til Microsoft 365 tenant først.'
    }
    $expires = $sync.State.GraphTokenExpires
    if ($expires -and ([datetime]$expires).ToUniversalTime() -gt (Get-Date).ToUniversalTime().AddMinutes(2)) {
        return [string]$sync.State.GraphAccessToken
    }
    if ([string]::IsNullOrWhiteSpace([string]$sync.State.GraphRefreshToken)) {
        throw 'Microsoft Graph token er udløbet. Forbind til Microsoft 365 tenant igen.'
    }

    $tenant = if ($sync.State.TenantId) { [string]$sync.State.TenantId } else { 'organizations' }
    $scope = (@($sync.configs.graphScopes) + @('offline_access','openid','profile') | Select-Object -Unique) -join ' '
    $body = @{
        client_id     = [string]$sync.State.GraphClientId
        scope         = $scope
        refresh_token = [string]$sync.State.GraphRefreshToken
        grant_type    = 'refresh_token'
    }
    $token = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token" -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
    $sync.State.GraphAccessToken = [string](Get-EbgObjectPropertyValue -InputObject $token -Name 'access_token')
    $newRefreshToken = [string](Get-EbgObjectPropertyValue -InputObject $token -Name 'refresh_token')
    if ($newRefreshToken) { $sync.State.GraphRefreshToken = $newRefreshToken }
    $expiresIn = [int](Get-EbgObjectPropertyValue -InputObject $token -Name 'expires_in')
    $sync.State.GraphTokenExpires = (Get-Date).ToUniversalTime().AddSeconds($expiresIn - 120)
    return [string]$sync.State.GraphAccessToken
}
