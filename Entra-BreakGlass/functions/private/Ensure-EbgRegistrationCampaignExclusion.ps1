function Ensure-EbgRegistrationCampaignExclusion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Group,
        [Parameter(Mandatory)][bool] $Apply
    )

    $groupId = [string](Get-EbgObjectPropertyValue -InputObject $Group -Name 'id')
    $groupName = [string](Get-EbgObjectPropertyValue -InputObject $Group -Name 'displayName')
    if ([string]::IsNullOrWhiteSpace($groupId)) {
        throw 'Kan ikke ekskludere fra registration campaign, fordi CA-BreakGlass-Exclude gruppen mangler Object ID.'
    }

    if (-not $Apply -or $sync.App.Mock) {
        return [pscustomobject]@{
            id = 'authenticationMethodsRegistrationCampaign'
            TargetGroupId = $groupId
            TargetGroupName = $groupName
            Status = if ($Apply) { 'Excluded' } else { 'PlannedExclude' }
            Detail = "Group $groupName is excluded from authentication methods registration campaign."
        }
    }

    $policy = Get-EbgAuthenticationMethodsPolicy
    $registrationEnforcement = Get-EbgObjectPropertyValue -InputObject $policy -Name 'registrationEnforcement'
    $campaign = Get-EbgObjectPropertyValue -InputObject $registrationEnforcement -Name 'authenticationMethodsRegistrationCampaign'
    if (-not $campaign) {
        return [pscustomobject]@{
            id = 'authenticationMethodsRegistrationCampaign'
            TargetGroupId = $groupId
            TargetGroupName = $groupName
            Status = 'NotConfigured'
            Detail = 'Authentication methods registration campaign was not present on the tenant policy.'
        }
    }

    $includeTargets = @()
    foreach ($target in @(Get-EbgObjectPropertyValue -InputObject $campaign -Name 'includeTargets')) {
        $targetId = [string](Get-EbgObjectPropertyValue -InputObject $target -Name 'id')
        if ([string]::IsNullOrWhiteSpace($targetId)) { continue }
        $item = @{
            id = $targetId
            targetType = [string](Get-EbgObjectPropertyValue -InputObject $target -Name 'targetType')
        }
        $method = [string](Get-EbgObjectPropertyValue -InputObject $target -Name 'targetedAuthenticationMethod')
        if (-not [string]::IsNullOrWhiteSpace($method)) {
            $item.targetedAuthenticationMethod = $method
        }
        $includeTargets += $item
    }

    $excludeTargets = @()
    $alreadyExcluded = $false
    foreach ($target in @(Get-EbgObjectPropertyValue -InputObject $campaign -Name 'excludeTargets')) {
        $targetId = [string](Get-EbgObjectPropertyValue -InputObject $target -Name 'id')
        if ([string]::IsNullOrWhiteSpace($targetId)) { continue }
        if ([string]::Equals($targetId, $groupId, [System.StringComparison]::OrdinalIgnoreCase)) {
            $alreadyExcluded = $true
        }
        $targetType = [string](Get-EbgObjectPropertyValue -InputObject $target -Name 'targetType')
        if ([string]::IsNullOrWhiteSpace($targetType)) { $targetType = 'group' }
        $excludeTargets += @{
            id = $targetId
            targetType = $targetType
        }
    }

    if ($alreadyExcluded) {
        return [pscustomobject]@{
            id = 'authenticationMethodsRegistrationCampaign'
            TargetGroupId = $groupId
            TargetGroupName = $groupName
            Status = 'AlreadyExcluded'
            Detail = "Group $groupName is already excluded from authentication methods registration campaign."
        }
    }

    $excludeTargets += @{
        id = $groupId
        targetType = 'group'
    }

    $campaignBody = @{
        includeTargets = @($includeTargets)
        excludeTargets = @($excludeTargets)
    }

    $state = [string](Get-EbgObjectPropertyValue -InputObject $campaign -Name 'state')
    if (-not [string]::IsNullOrWhiteSpace($state)) { $campaignBody.state = $state }

    $snooze = Get-EbgObjectPropertyValue -InputObject $campaign -Name 'snoozeDurationInDays'
    if ($null -ne $snooze) { $campaignBody.snoozeDurationInDays = $snooze }

    $enforce = Get-EbgObjectPropertyValue -InputObject $campaign -Name 'enforceRegistrationAfterAllowedSnoozes'
    if ($null -ne $enforce) { $campaignBody.enforceRegistrationAfterAllowedSnoozes = [bool]$enforce }

    Write-EbgLog -Message "Ekskluderer $groupName fra Authentication Methods registration campaign."
    Invoke-EbgGraphRequest -Method PATCH -Uri 'https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy' -Body @{
        registrationEnforcement = @{
            authenticationMethodsRegistrationCampaign = $campaignBody
        }
    } | Out-Null

    return [pscustomobject]@{
        id = 'authenticationMethodsRegistrationCampaign'
        TargetGroupId = $groupId
        TargetGroupName = $groupName
        Status = 'Excluded'
        Detail = "Group $groupName is excluded from authentication methods registration campaign."
    }
}
