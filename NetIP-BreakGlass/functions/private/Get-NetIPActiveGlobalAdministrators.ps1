function Get-NetIPActiveGlobalAdministrators {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) {
        return @(
            [pscustomobject]@{
                id = 'mock-ga-1'
                displayName = 'Mock Global Admin'
                userPrincipalName = 'mock.globaladmin@contoso.onmicrosoft.com'
                accountEnabled = $true
                assignmentType = 'Direct Global Administrator assignment'
            }
        )
    }

    $role = Get-NetIPGlobalAdministratorRoleDefinition
    $roleId = [string](Get-NetIPObjectPropertyValue -InputObject $role -Name 'id')
    if ([string]::IsNullOrWhiteSpace($roleId)) {
        return @()
    }

    $filter = [uri]::EscapeDataString("roleDefinitionId eq '$roleId'")
    $assignments = @(Get-NetIPGraphCollection -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=$filter&`$select=id,principalId,roleDefinitionId,directoryScopeId")
    $admins = New-Object System.Collections.Generic.List[object]

    foreach ($assignment in $assignments) {
        $principalId = [string](Get-NetIPObjectPropertyValue -InputObject $assignment -Name 'principalId')
        if ([string]::IsNullOrWhiteSpace($principalId)) { continue }

        try {
            $user = Invoke-NetIPGraphRequest -Method GET -Uri ("https://graph.microsoft.com/v1.0/users/{0}?`$select=id,displayName,userPrincipalName,accountEnabled" -f [uri]::EscapeDataString($principalId)) -SuppressNotFoundLog
            $enabled = [bool](Get-NetIPObjectPropertyValue -InputObject $user -Name 'accountEnabled')
            if (-not $enabled) { continue }

            $admins.Add([pscustomobject]@{
                id = [string](Get-NetIPObjectPropertyValue -InputObject $user -Name 'id')
                displayName = [string](Get-NetIPObjectPropertyValue -InputObject $user -Name 'displayName')
                userPrincipalName = [string](Get-NetIPObjectPropertyValue -InputObject $user -Name 'userPrincipalName')
                accountEnabled = $enabled
                assignmentType = 'Direct Global Administrator assignment'
            })
        }
        catch {
            Write-NetIPLog -Level WARN -Message "Springer Global Administrator principal over, fordi den ikke kunne læses som aktiv bruger: $principalId"
        }
    }

    return @($admins | Sort-Object userPrincipalName -Unique)
}
