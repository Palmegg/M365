function Get-NetIPGlobalAdministratorRoleDefinition {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) {
        return [pscustomobject]@{
            id = 'mock-global-admin-role-definition'
            displayName = 'Global Administrator'
        }
    }

    $filter = [uri]::EscapeDataString("displayName eq 'Global Administrator'")
    $roles = @(Get-NetIPGraphCollection -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?`$filter=$filter&`$select=id,displayName")
    $role = $roles | Select-Object -First 1
    if (-not $role) {
        throw 'Kunne ikke finde role definition for Global Administrator via Microsoft Graph.'
    }
    return $role
}
