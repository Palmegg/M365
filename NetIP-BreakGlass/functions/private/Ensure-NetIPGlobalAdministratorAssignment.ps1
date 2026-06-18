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
        Write-NetIPLog -Level PASS -Message "Administratorrolle håndteret: $upn -> $roleName"
        return [pscustomobject]@{
            UserPrincipalName = $upn
            Role = $roleName
            Scope = '/'
            Status = if ($Apply) { 'Assigned' } else { 'Planned' }
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
    Write-NetIPLog -Message "Tildeler $roleName til $upn..."
    try {
        Invoke-NetIPGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' -Body $body | Out-Null
        Write-NetIPLog -Level PASS -Message "Administratorrolle tildelt: $upn -> $roleName"
        return [pscustomobject]@{
            UserPrincipalName = $upn
            Role = $roleName
            Scope = '/'
            Status = 'Assigned'
            Detail = ''
        }
    }
    catch {
        $message = [string]$_
        if ($message -match 'already exist|already exists|conflicting object|RoleAssignmentExists|role assignment already') {
            Write-NetIPLog -Level PASS -Message "Administratorrolle findes allerede: $upn -> $roleName"
            return [pscustomobject]@{
                UserPrincipalName = $upn
                Role = $roleName
                Scope = '/'
                Status = 'AlreadyAssigned'
                Detail = ''
            }
        }
        throw
    }
}
