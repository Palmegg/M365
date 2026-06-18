function Ensure-EbgFido2AuthenticationMethodPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Group,
        [Parameter(Mandatory)][bool] $Apply
    )

    $groupId = [string](Get-EbgObjectPropertyValue -InputObject $Group -Name 'id')
    $groupName = [string](Get-EbgObjectPropertyValue -InputObject $Group -Name 'displayName')
    if ([string]::IsNullOrWhiteSpace($groupId)) {
        throw 'Kan ikke konfigurere FIDO2/passkey policy, fordi CA-BreakGlass-Exclude gruppen mangler Object ID.'
    }

    if (-not $Apply -or $sync.App.Mock) {
        return [pscustomobject]@{
            id = 'Fido2'
            displayName = 'FIDO2/passkey authentication method policy'
            state = 'enabled'
            TargetGroupId = $groupId
            TargetGroupName = $groupName
            Status = if ($Apply) { 'Updated' } else { 'PlannedUpdate' }
            Detail = "FIDO2/passkey enabled for group $groupName."
        }
    }

    $policy = Get-EbgFido2AuthenticationMethodPolicy
    $includeTargets = @(Get-EbgObjectPropertyValue -InputObject $policy -Name 'includeTargets')
    $passkeyProfiles = @(Get-EbgObjectPropertyValue -InputObject $policy -Name 'passkeyProfiles')
    $defaultProfileId = [string](($passkeyProfiles | ForEach-Object {
        [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id')
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1))
    if ([string]::IsNullOrWhiteSpace($defaultProfileId)) {
        $defaultProfileId = '00000000-0000-0000-0000-000000000001'
    }

    $state = [string](Get-EbgObjectPropertyValue -InputObject $policy -Name 'state')
    $selfService = [bool](Get-EbgObjectPropertyValue -InputObject $policy -Name 'isSelfServiceRegistrationAllowed')
    $hasAllUsers = $false
    $hasTargetGroup = $false
    $normalizedTargets = @()

    foreach ($target in $includeTargets) {
        $targetId = [string](Get-EbgObjectPropertyValue -InputObject $target -Name 'id')
        if ([string]::IsNullOrWhiteSpace($targetId)) { continue }

        if ([string]::Equals($targetId, 'all_users', [System.StringComparison]::OrdinalIgnoreCase)) { $hasAllUsers = $true }
        if ([string]::Equals($targetId, $groupId, [System.StringComparison]::OrdinalIgnoreCase)) { $hasTargetGroup = $true }

        $targetType = [string](Get-EbgObjectPropertyValue -InputObject $target -Name 'targetType')
        if ([string]::IsNullOrWhiteSpace($targetType)) { $targetType = 'group' }

        $allowedProfiles = @(Get-EbgObjectPropertyValue -InputObject $target -Name 'allowedPasskeyProfiles') | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        } | ForEach-Object { [string]$_ }
        if ($allowedProfiles.Count -lt 1) { $allowedProfiles = @($defaultProfileId) }

        $normalizedTargets += @{
            targetType = $targetType
            id = $targetId
            isRegistrationRequired = [bool](Get-EbgObjectPropertyValue -InputObject $target -Name 'isRegistrationRequired')
            allowedPasskeyProfiles = @($allowedProfiles)
        }
    }

    if ($state -eq 'enabled' -and $selfService -and ($hasAllUsers -or $hasTargetGroup)) {
        return [pscustomobject]@{
            id = 'Fido2'
            displayName = 'FIDO2/passkey authentication method policy'
            state = $state
            TargetGroupId = $groupId
            TargetGroupName = $groupName
            Status = 'AlreadyConfigured'
            Detail = if ($hasAllUsers) { 'FIDO2/passkey is enabled for all users.' } else { "FIDO2/passkey is already enabled for group $groupName." }
        }
    }

    if (-not $hasAllUsers -and -not $hasTargetGroup) {
        $normalizedTargets += @{
            targetType = 'group'
            id = $groupId
            isRegistrationRequired = $false
            allowedPasskeyProfiles = @($defaultProfileId)
        }
    }

    Write-EbgLog -Message "Opdaterer FIDO2/passkey Authentication Method policy, så $groupName kan registrere security keys."
    $body = @{
        '@odata.type' = '#microsoft.graph.fido2AuthenticationMethodConfiguration'
        id = 'Fido2'
        state = 'enabled'
        isSelfServiceRegistrationAllowed = $true
        includeTargets = @($normalizedTargets)
    }
    Invoke-EbgGraphRequest -Method PATCH -Uri 'https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2' -Body $body | Out-Null

    return [pscustomobject]@{
        id = 'Fido2'
        displayName = 'FIDO2/passkey authentication method policy'
        state = 'enabled'
        TargetGroupId = $groupId
        TargetGroupName = $groupName
        Status = 'Updated'
        Detail = "FIDO2/passkey enabled for group $groupName."
    }
}
