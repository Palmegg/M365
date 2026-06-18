function Test-EbgTemporaryAccessPassPrerequisite {
    [CmdletBinding()]
    param()

    $requiredRoleNames = @('Authentication Administrator', 'Privileged Authentication Administrator')
    $requiredScopeName = 'UserAuthMethod-TAP.ReadWrite.All'
    if ($sync.App.Mock) {
        return [pscustomobject]@{
            Allowed = $true
            Account = [string]$sync.State.GraphAccount
            MatchedRoles = @('Mock Authentication Administrator')
            RequiredRoles = $requiredRoleNames
            RequiredScope = $requiredScopeName
            HasRequiredScope = $true
            Detail = 'Mock mode.'
        }
    }

    Write-EbgLog -Message 'Pre-check: kontrollerer om operator kan oprette Temporary Access Pass...'
    $context = Get-MgContext -ErrorAction Stop
    $currentScopes = @($context.Scopes)
    $hasRequiredScope = $currentScopes -contains $requiredScopeName
    if ($hasRequiredScope) {
        Write-EbgLog -Level PASS -Message "TAP pre-check OK: token har scope $requiredScopeName."
    }
    else {
        Write-EbgLog -Level WARN -Message "TAP pre-check fejlede: token mangler scope $requiredScopeName. Aktuelle scopes: $($currentScopes -join ', ')"
    }

    $me = Invoke-EbgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=id,displayName,userPrincipalName'
    $operatorId = [string](Get-EbgObjectPropertyValue -InputObject $me -Name 'id')
    $operatorUpn = [string](Get-EbgObjectPropertyValue -InputObject $me -Name 'userPrincipalName')
    if ([string]::IsNullOrWhiteSpace($operatorId)) {
        throw 'Kunne ikke læse object ID for den indloggede Graph-konto.'
    }

    $memberGroupIds = @()
    try {
        $groups = @(Get-EbgGraphCollection -Uri 'https://graph.microsoft.com/v1.0/me/transitiveMemberOf/microsoft.graph.group?$select=id,displayName')
        $memberGroupIds = @($groups | ForEach-Object { [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id') } | Where-Object { $_ })
    }
    catch {
        Write-EbgLog -Level WARN -Message 'Kunne ikke læse operatorens transitive gruppemedlemskaber til TAP role pre-check. Fortsætter med direkte rollecheck.'
    }

    $matchedRoles = @()
    foreach ($roleName in $requiredRoleNames) {
        $filter = [uri]::EscapeDataString("displayName eq '$roleName'")
        $roleDefinitions = @(Get-EbgGraphCollection -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?`$filter=$filter&`$select=id,displayName")
        $roleDefinition = $roleDefinitions | Select-Object -First 1
        $roleDefinitionId = [string](Get-EbgObjectPropertyValue -InputObject $roleDefinition -Name 'id')
        if ([string]::IsNullOrWhiteSpace($roleDefinitionId)) {
            Write-EbgLog -Level WARN -Message "Kunne ikke finde role definition: $roleName"
            continue
        }

        $assignmentFilter = [uri]::EscapeDataString("roleDefinitionId eq '$roleDefinitionId'")
        $assignments = @(Get-EbgGraphCollection -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=$assignmentFilter&`$select=id,principalId,roleDefinitionId,directoryScopeId")
        foreach ($assignment in $assignments) {
            $principalId = [string](Get-EbgObjectPropertyValue -InputObject $assignment -Name 'principalId')
            if ($principalId -eq $operatorId -or ($memberGroupIds -contains $principalId)) {
                $matchedRoles += $roleName
                break
            }
        }
    }

    $matchedRoles = @($matchedRoles | Select-Object -Unique)
    $hasRequiredRole = $matchedRoles.Count -gt 0
    $allowed = $hasRequiredRole -and $hasRequiredScope
    if ($hasRequiredRole) {
        Write-EbgLog -Level PASS -Message "TAP pre-check OK: $operatorUpn har $($matchedRoles -join ', ')."
    }
    else {
        Write-EbgLog -Level WARN -Message "TAP pre-check fejlede: $operatorUpn har ikke Authentication Administrator eller Privileged Authentication Administrator."
    }

    return [pscustomobject]@{
        Allowed = $allowed
        Account = $operatorUpn
        MatchedRoles = $matchedRoles
        RequiredRoles = $requiredRoleNames
        RequiredScope = $requiredScopeName
        HasRequiredScope = $hasRequiredScope
        Detail = if ($allowed) { 'OK' } elseif (-not $hasRequiredScope) { "Temporary Access Pass kræver Graph delegated scope $requiredScopeName." } else { 'Temporary Access Pass kræver Authentication Administrator eller Privileged Authentication Administrator for delegated Graph.' }
    }
}
