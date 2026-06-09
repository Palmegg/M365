function Add-NetIPGroupExclusionToCAPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]] $Policies,
        [Parameter(Mandatory)][string] $GroupId,
        [Parameter(Mandatory)][bool] $Apply
    )

    $results = @()
    foreach ($policy in $Policies) {
        $policyId = [string](Get-NetIPObjectPropertyValue -InputObject $policy -Name 'id')
        $policyName = [string](Get-NetIPObjectPropertyValue -InputObject $policy -Name 'displayName')
        $conditions = Get-NetIPObjectPropertyValue -InputObject $policy -Name 'conditions'
        $users = Get-NetIPObjectPropertyValue -InputObject $conditions -Name 'users'
        if (-not $users) {
            $users = [pscustomobject]@{}
        }
        $excludeGroups = @(Get-NetIPObjectPropertyValue -InputObject $users -Name 'excludeGroups')
        if ($excludeGroups -contains $GroupId) {
            $results += [pscustomobject]@{ Policy = $policyName; PolicyId = $policyId; Status = 'AlreadyExcluded'; Warning = '' }
            continue
        }
        $updatedUsers = ConvertTo-NetIPPlainHashtable -InputObject $users
        if (-not $updatedUsers) { $updatedUsers = @{} }
        $updatedUsers['excludeGroups'] = @($excludeGroups + $GroupId | Select-Object -Unique)
        $body = @{ conditions = @{ users = $updatedUsers } }
        if (-not $Apply) {
            $results += [pscustomobject]@{ Policy = $policyName; PolicyId = $policyId; Status = 'PlannedPatch'; Warning = '' }
            continue
        }
        if ($sync.App.Mock) {
            $results += [pscustomobject]@{ Policy = $policyName; PolicyId = $policyId; Status = 'Patched'; Warning = '' }
            continue
        }
        try {
            Invoke-NetIPGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$policyId" -Body $body | Out-Null
            $results += [pscustomobject]@{ Policy = $policyName; PolicyId = $policyId; Status = 'Patched'; Warning = '' }
        }
        catch {
            $warning = "Conditional Access-politikken '$policyName' kunne ikke opdateres."
            $sync.State.Warnings += $warning
            Write-NetIPLog -Level WARN -Message "$warning $(ConvertTo-NetIPRedactedError -ErrorRecord $_)"
            $results += [pscustomobject]@{ Policy = $policyName; PolicyId = $policyId; Status = 'Failed'; Warning = $warning }
        }
    }
    return $results
}
