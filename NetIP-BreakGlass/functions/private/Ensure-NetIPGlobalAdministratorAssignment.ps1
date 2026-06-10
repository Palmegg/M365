function Ensure-NetIPGlobalAdministratorAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $User,
        [Parameter(Mandatory)] $RoleDefinition,
        [Parameter(Mandatory)][bool] $Apply
    )

    $userId = [string](Get-NetIPObjectPropertyValue -InputObject $User -Name 'id')
    $upn = [string](Get-NetIPObjectPropertyValue -InputObject $User -Name 'userPrincipalName')
    $roleDefinitionId = [string](Get-NetIPObjectPropertyValue -InputObject $RoleDefinition -Name 'id')
    $roleName = [string](Get-NetIPObjectPropertyValue -InputObject $RoleDefinition -Name 'displayName')

    if ([string]::IsNullOrWhiteSpace($userId) -or [string]::IsNullOrWhiteSpace($roleDefinitionId)) {
        return [pscustomobject]@{
            UserPrincipalName = $upn
            Role = $roleName
            Scope = '/'
            Status = 'Skipped'
            Detail = 'User or role definition missing.'
        }
    }

    if ($sync.App.Mock -or $userId -like 'mock-*') {
        return [pscustomobject]@{
            UserPrincipalName = $upn
            Role = $roleName
            Scope = '/'
            Status = if ($Apply) { 'Assigned' } else { 'Planned' }
            Detail = ''
        }
    }

    $filter = [uri]::EscapeDataString("principalId eq '$userId' and roleDefinitionId eq '$roleDefinitionId' and directoryScopeId eq '/'")
    $existing = @(Get-NetIPGraphCollection -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=$filter&`$select=id,principalId,roleDefinitionId,directoryScopeId")
    if ($existing.Count -gt 0) {
        return [pscustomobject]@{
            UserPrincipalName = $upn
            Role = $roleName
            Scope = '/'
            Status = 'AlreadyAssigned'
            Detail = ''
        }
    }

    if (-not $Apply) {
        return [pscustomobject]@{
            UserPrincipalName = $upn
            Role = $roleName
            Scope = '/'
            Status = 'Planned'
            Detail = ''
        }
    }

    $body = @{
        principalId = $userId
        roleDefinitionId = $roleDefinitionId
        directoryScopeId = '/'
    }
    Invoke-NetIPGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' -Body $body | Out-Null
    return [pscustomobject]@{
        UserPrincipalName = $upn
        Role = $roleName
        Scope = '/'
        Status = 'Assigned'
        Detail = ''
    }
}
