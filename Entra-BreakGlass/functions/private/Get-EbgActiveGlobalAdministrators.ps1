function Get-EbgActiveGlobalAdministrators {
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
                label = 'Mock Global Admin <mock.globaladmin@contoso.onmicrosoft.com>'
            },
            [pscustomobject]@{
                id = 'mock-ga-2'
                displayName = 'Mock Emergency Admin'
                userPrincipalName = 'mock.emergencyadmin@contoso.onmicrosoft.com'
                accountEnabled = $true
                assignmentType = 'Direct Global Administrator assignment'
                label = 'Mock Emergency Admin <mock.emergencyadmin@contoso.onmicrosoft.com>'
            }
        )
    }

    $role = Get-EbgGlobalAdministratorRoleDefinition
    $roleId = [string](Get-EbgObjectPropertyValue -InputObject $role -Name 'id')
    if ([string]::IsNullOrWhiteSpace($roleId)) {
        return @()
    }

    $filter = [uri]::EscapeDataString("roleDefinitionId eq '$roleId'")
    $assignments = @(Get-EbgGraphCollection -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=$filter&`$select=id,principalId,roleDefinitionId,directoryScopeId")
    $admins = New-Object System.Collections.Generic.List[object]

    foreach ($assignment in $assignments) {
        $principalId = [string](Get-EbgObjectPropertyValue -InputObject $assignment -Name 'principalId')
        if ([string]::IsNullOrWhiteSpace($principalId)) { continue }

        try {
            $user = Invoke-EbgGraphRequest -Method GET -Uri ("https://graph.microsoft.com/v1.0/users/{0}?`$select=id,displayName,userPrincipalName,accountEnabled" -f [uri]::EscapeDataString($principalId)) -SuppressNotFoundLog
            $enabled = [bool](Get-EbgObjectPropertyValue -InputObject $user -Name 'accountEnabled')
            if (-not $enabled) { continue }

            $admins.Add([pscustomobject]@{
                id = [string](Get-EbgObjectPropertyValue -InputObject $user -Name 'id')
                displayName = [string](Get-EbgObjectPropertyValue -InputObject $user -Name 'displayName')
                userPrincipalName = [string](Get-EbgObjectPropertyValue -InputObject $user -Name 'userPrincipalName')
                accountEnabled = $enabled
                assignmentType = 'Direct Global Administrator assignment'
                label = ('{0} <{1}>' -f [string](Get-EbgObjectPropertyValue -InputObject $user -Name 'displayName'), [string](Get-EbgObjectPropertyValue -InputObject $user -Name 'userPrincipalName'))
            })
        }
        catch {
            Write-EbgLog -Level WARN -Message "Springer Global Administrator principal over, fordi den ikke kunne læses som aktiv bruger: $principalId"
        }
    }

    return @($admins | Sort-Object userPrincipalName -Unique)
}
