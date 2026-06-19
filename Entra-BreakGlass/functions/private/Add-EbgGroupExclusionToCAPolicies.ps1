function Add-EbgGroupExclusionToCAPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]] $Policies,
        [Parameter(Mandatory)][string] $GroupId,
        [Parameter(Mandatory)][bool] $Apply
    )

    $results = @()
    $policyList = @($Policies)
    $total = $policyList.Count
    $index = 0
    foreach ($policy in $policyList) {
        $index++
        $policyId = [string](Get-EbgObjectPropertyValue -InputObject $policy -Name 'id')
        $policyName = [string](Get-EbgObjectPropertyValue -InputObject $policy -Name 'displayName')
        Write-EbgStatus -Busy -Message "Phase 1a step 11/12: CA policy $index/$total - $policyName"
        Write-EbgLog -Message "CA exclusion $index/${total}: $policyName ($policyId)"
        Invoke-EbgDoEvents

        $conditions = Get-EbgObjectPropertyValue -InputObject $policy -Name 'conditions'
        $users = Get-EbgObjectPropertyValue -InputObject $conditions -Name 'users'
        if (-not $users) {
            $users = [pscustomobject]@{}
        }
        $excludeGroups = @(Get-EbgObjectPropertyValue -InputObject $users -Name 'excludeGroups')
        if ($excludeGroups -contains $GroupId) {
            Write-EbgLog -Level PASS -Message "CA policy springes over, gruppen er allerede ekskluderet: $policyName"
            $results += [pscustomobject]@{ Policy = $policyName; PolicyId = $policyId; Status = 'AlreadyExcluded'; Warning = '' }
            Invoke-EbgDoEvents
            continue
        }
        $updatedUsers = ConvertTo-EbgConditionalAccessUsersPatch -Users $users -GroupId $GroupId
        if (-not $updatedUsers) {
            $warning = "Conditional Access-politikken '$policyName' kunne ikke opdateres, fordi users condition ikke kunne normaliseres til Graph schema."
            $sync.State.Warnings += $warning
            Write-EbgLog -Level WARN -Message $warning
            $results += [pscustomobject]@{ Policy = $policyName; PolicyId = $policyId; Status = 'Failed'; Warning = $warning }
            Invoke-EbgDoEvents
            continue
        }
        $body = @{ conditions = @{ users = $updatedUsers } }
        if (-not $Apply) {
            $results += [pscustomobject]@{ Policy = $policyName; PolicyId = $policyId; Status = 'PlannedPatch'; Warning = '' }
            Invoke-EbgDoEvents
            continue
        }
        if ($sync.App.Mock) {
            Write-EbgLog -Level PASS -Message "CA policy patched i mock mode: $policyName"
            $results += [pscustomobject]@{ Policy = $policyName; PolicyId = $policyId; Status = 'Patched'; Warning = '' }
            Invoke-EbgDoEvents
            continue
        }
        try {
            Invoke-EbgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$policyId" -Body $body -SuppressErrorLog | Out-Null
            Write-EbgLog -Level PASS -Message "CA policy patched: $policyName"
            $results += [pscustomobject]@{ Policy = $policyName; PolicyId = $policyId; Status = 'Patched'; Warning = '' }
        }
        catch {
            $warning = "Conditional Access-politikken '$policyName' kunne ikke opdateres."
            $sync.State.Warnings += $warning
            $errorSummary = @((ConvertTo-EbgRedactedError -ErrorRecord $_) -split "`r?`n" | Where-Object { $_ } | Select-Object -First 1)
            Write-EbgLog -Level WARN -Message "$warning $errorSummary"
            $results += [pscustomobject]@{ Policy = $policyName; PolicyId = $policyId; Status = 'Failed'; Warning = $warning }
        }
        Invoke-EbgDoEvents
    }
    return $results
}
