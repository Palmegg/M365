function Get-EbgGlobalAdministratorRoleDefinition {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) {
        return [pscustomobject]@{
            id = 'mock-global-admin-role-definition'
            displayName = 'Global Administrator'
        }
    }

    Write-EbgLog -Message 'Henter role definition: Global Administrator...'
    $filter = [uri]::EscapeDataString("displayName eq 'Global Administrator'")
    $roles = @(Get-EbgGraphCollection -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?`$filter=$filter&`$select=id,displayName")
    $role = $roles | Select-Object -First 1
    if (-not $role) {
        throw 'Kunne ikke finde role definition for Global Administrator via Microsoft Graph.'
    }
    Write-EbgLog -Level PASS -Message 'Role definition fundet: Global Administrator'
    return $role
}