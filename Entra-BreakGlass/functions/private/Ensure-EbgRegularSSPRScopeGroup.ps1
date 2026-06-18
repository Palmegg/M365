function ConvertTo-EbgMailNickname {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $DisplayName)

    $nickname = ($DisplayName -replace '[^a-zA-Z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($nickname)) { $nickname = 'BreakGlassSSPRScope' }
    if ($nickname.Length -gt 64) { $nickname = $nickname.Substring(0, 64) }
    return $nickname
}

function New-EbgRegularSSPRMembershipRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Account1ObjectId,
        [Parameter(Mandatory)][string] $Account2ObjectId
    )

    return '(user.accountEnabled -eq true) -and (user.userType -eq "Member") -and (user.objectId -notIn ["{0}","{1}"])' -f $Account1ObjectId, $Account2ObjectId
}

function Ensure-EbgRegularSSPRScopeGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][string] $Description,
        [Parameter(Mandatory)][object[]] $BreakGlassUsers,
        [Parameter(Mandatory)][bool] $CreateOrUpdate,
        [Parameter(Mandatory)][bool] $Apply
    )

    $validUsers = @($BreakGlassUsers | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id')) })
    if ($validUsers.Count -lt 2) {
        throw 'Kan ikke oprette SSPR scope-gruppe, fordi begge break-glass konti skal have Object ID først.'
    }

    $account1Id = [string](Get-EbgObjectPropertyValue -InputObject $validUsers[0] -Name 'id')
    $account2Id = [string](Get-EbgObjectPropertyValue -InputObject $validUsers[1] -Name 'id')
    $membershipRule = New-EbgRegularSSPRMembershipRule -Account1ObjectId $account1Id -Account2ObjectId $account2Id

    if (-not $CreateOrUpdate) {
        return [pscustomobject]@{
            DisplayName = $DisplayName
            Id = ''
            Status = 'Skipped'
            MembershipRule = $membershipRule
            ManualAction = 'Regular SSPR scoping was not selected.'
        }
    }

    if ($sync.App.Mock) {
        return [pscustomobject]@{
            DisplayName = $DisplayName
            Id = 'mock-sspr-scope-group'
            Status = if ($Apply) { 'CreatedOrUpdated' } else { 'PlannedCreateOrUpdate' }
            MembershipRule = $membershipRule
            ManualAction = "Set regular SSPR to Selected and choose $DisplayName in Entra Password reset settings."
        }
    }

    $group = Get-EbgGroupByDisplayName -DisplayName $DisplayName
    $body = @{
        description = $Description
        membershipRule = $membershipRule
        membershipRuleProcessingState = 'On'
    }

    if ($group) {
        $groupId = [string](Get-EbgObjectPropertyValue -InputObject $group -Name 'id')
        $groupTypes = @(Get-EbgObjectPropertyValue -InputObject $group -Name 'groupTypes')
        $isDynamic = $groupTypes -contains 'DynamicMembership'
        if (-not $isDynamic) {
            throw "SSPR scope-gruppen '$DisplayName' findes allerede, men er ikke en dynamic membership group. Omdøb/slet den manuelt eller vælg et andet gruppenavn."
        }
        $currentRule = [string](Get-EbgObjectPropertyValue -InputObject $group -Name 'membershipRule')
        $currentDescription = [string](Get-EbgObjectPropertyValue -InputObject $group -Name 'description')
        $needsUpdate = ($currentRule -ne $membershipRule) -or ($currentDescription -ne $Description)
        if ($Apply -and $needsUpdate) {
            Write-EbgLog -Message "Opdaterer regular SSPR scope-gruppe: $DisplayName"
            Invoke-EbgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/groups/$groupId" -Body $body | Out-Null
            $status = 'Updated'
        }
        elseif ($needsUpdate) {
            $status = 'PlannedUpdate'
        }
        else {
            $status = 'AlreadyCorrect'
        }

        return [pscustomobject]@{
            DisplayName = $DisplayName
            Id = $groupId
            Status = $status
            MembershipRule = $membershipRule
            ManualAction = "Set regular SSPR to Selected and choose $DisplayName in Entra Password reset settings."
        }
    }

    if (-not $Apply) {
        return [pscustomobject]@{
            DisplayName = $DisplayName
            Id = 'planned-sspr-scope-group'
            Status = 'PlannedCreate'
            MembershipRule = $membershipRule
            ManualAction = "Set regular SSPR to Selected and choose $DisplayName in Entra Password reset settings."
        }
    }

    $createBody = @{
        displayName = $DisplayName
        description = $Description
        mailEnabled = $false
        mailNickname = ConvertTo-EbgMailNickname -DisplayName $DisplayName
        securityEnabled = $true
        groupTypes = @('DynamicMembership')
        membershipRule = $membershipRule
        membershipRuleProcessingState = 'On'
    }
    Write-EbgLog -Message "Opretter regular SSPR scope-gruppe: $DisplayName"
    Invoke-EbgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/groups' -Body $createBody | Out-Null
    $created = Get-EbgGroupByDisplayName -DisplayName $DisplayName
    return [pscustomobject]@{
        DisplayName = $DisplayName
        Id = [string](Get-EbgObjectPropertyValue -InputObject $created -Name 'id')
        Status = 'Created'
        MembershipRule = $membershipRule
        ManualAction = "Set regular SSPR to Selected and choose $DisplayName in Entra Password reset settings."
    }
}
