function Get-NetIPTenantInfo {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) {
        $info = [pscustomobject]@{
            TenantId          = '00000000-0000-0000-0000-000000000001'
            TenantDisplayName = 'Contoso Demo Tenant'
            OnMicrosoftDomain = 'contoso.onmicrosoft.com'
        }
        $sync.State.TenantId = $info.TenantId
        $sync.State.TenantDisplayName = $info.TenantDisplayName
        $sync.State.OnMicrosoftDomain = $info.OnMicrosoftDomain
        return $info
    }

    $org = Get-NetIPGraphCollection -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,verifiedDomains' | Select-Object -First 1
    if (-not $org) { throw 'Kunne ikke læse tenant information fra Microsoft Graph.' }
    $info = [pscustomobject]@{
        TenantId          = [string](Get-NetIPObjectPropertyValue -InputObject $org -Name 'id')
        TenantDisplayName = [string](Get-NetIPObjectPropertyValue -InputObject $org -Name 'displayName')
        OnMicrosoftDomain = Get-NetIPOnMicrosoftDomain -Organization $org
    }
    $sync.State.TenantId = $info.TenantId
    $sync.State.TenantDisplayName = $info.TenantDisplayName
    $sync.State.OnMicrosoftDomain = $info.OnMicrosoftDomain
    return $info
}
