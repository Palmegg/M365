function Get-EbgTenantInfo {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) {
        $info = [pscustomobject]@{
            TenantId          = '00000000-0000-0000-0000-000000000001'
            TenantDisplayName = 'Contoso Demo Tenant'
            OnMicrosoftDomain = 'contoso.onmicrosoft.com'
            VerifiedDomains   = @('contoso.onmicrosoft.com')
        }
        $sync.State.TenantId = $info.TenantId
        $sync.State.TenantDisplayName = $info.TenantDisplayName
        $sync.State.OnMicrosoftDomain = $info.OnMicrosoftDomain
        return $info
    }

    Write-EbgLog -Message 'Tenant info: henter organization fra Microsoft Graph...'
    $organizationResponse = Invoke-EbgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,verifiedDomains'
    $org = @(Get-EbgObjectPropertyValue -InputObject $organizationResponse -Name 'value') | Select-Object -First 1
    if (-not $org) { throw 'Kunne ikke læse tenant information fra Microsoft Graph.' }
    Write-EbgLog -Message 'Tenant info: organization response modtaget, parser verified domains...'
    $info = [pscustomobject]@{
        TenantId          = [string](Get-EbgObjectPropertyValue -InputObject $org -Name 'id')
        TenantDisplayName = [string](Get-EbgObjectPropertyValue -InputObject $org -Name 'displayName')
        OnMicrosoftDomain = Get-EbgOnMicrosoftDomain -Organization $org
        VerifiedDomains   = @((Get-EbgObjectPropertyValue -InputObject $org -Name 'verifiedDomains') | ForEach-Object { [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'name') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    Write-EbgLog -Message "Tenant info: $($info.TenantDisplayName) / $($info.TenantId) / $($info.OnMicrosoftDomain)"
    $sync.State.TenantId = $info.TenantId
    $sync.State.TenantDisplayName = $info.TenantDisplayName
    $sync.State.OnMicrosoftDomain = $info.OnMicrosoftDomain
    return $info
}
