function New-NetIPPlanObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config,
        [AllowNull()] $Discovery = $null
    )

    $tenant = Get-NetIPTenantInfo
    $upn1 = ConvertTo-BreakGlassUpn -Prefix $Config.UserPrefix1 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
    $upn2 = ConvertTo-BreakGlassUpn -Prefix $Config.UserPrefix2 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
    $user1 = if ($Discovery) { $Discovery.User1 } else { Get-NetIPUserByUpn -UserPrincipalName $upn1 }
    $user2 = if ($Discovery) { $Discovery.User2 } else { Get-NetIPUserByUpn -UserPrincipalName $upn2 }
    $group = if ($Discovery) { $Discovery.Group } else { Get-NetIPGroupByDisplayName -DisplayName $Config.GroupName }
    $policies = if ($Discovery) { @($Discovery.CAPolicies) } else { @(Get-NetIPConditionalAccessPolicies) }

    $alreadyExcluded = @()
    $toPatch = @()
    if ($group -and $group.id) {
        foreach ($policy in $policies) {
            $excludeGroups = @(Get-NetIPObjectPropertyValue -InputObject (Get-NetIPObjectPropertyValue -InputObject (Get-NetIPObjectPropertyValue -InputObject $policy -Name 'conditions') -Name 'users') -Name 'excludeGroups')
            if ($excludeGroups -contains $group.id) { $alreadyExcluded += $policy }
            elseif ($Config.PatchCAPolicies) { $toPatch += $policy }
        }
    }
    elseif ($Config.PatchCAPolicies) {
        $toPatch = @($policies)
    }

    $warnings = @()
    if ($user1) { $warnings += 'Konto 1 findes allerede. Password bliver ikke ændret automatisk.' }
    if ($user2) { $warnings += 'Konto 2 findes allerede. Password bliver ikke ændret automatisk.' }
    $warnings += 'Begge break-glass konti får direkte Global Administrator rolle på tenant scope (/).'
    if ($Config.PatchCAPolicies) { $warnings += 'Eksisterende Conditional Access-politikker ændres. Backup oprettes før ændringer.' }

    $outputFolder = if ($sync.State.OutputFolder) { $sync.State.OutputFolder } else { Join-Path $sync.App.OutputRoot ('BreakGlass-{0}-<timestamp>' -f $tenant.TenantId) }
    $plan = [pscustomobject]@{
        TenantId                  = $tenant.TenantId
        TenantDisplayName         = $tenant.TenantDisplayName
        OnMicrosoftDomain         = $tenant.OnMicrosoftDomain
        Account1DisplayName       = $Config.DisplayName1
        Account1UPN               = $upn1
        Account1Status            = if ($user1) { 'Eksisterer allerede' } elseif ($Config.CreateUsers) { 'Oprettes' } else { 'Springes over' }
        Account2DisplayName       = $Config.DisplayName2
        Account2UPN               = $upn2
        Account2Status            = if ($user2) { 'Eksisterer allerede' } elseif ($Config.CreateUsers) { 'Oprettes' } else { 'Springes over' }
        GroupName                 = $Config.GroupName
        GroupStatus               = if ($group) { 'Eksisterer allerede' } elseif ($Config.CreateGroup) { 'Oprettes' } else { 'Springes over' }
        AddAccountsToGroup        = [bool]$Config.AddUsersToGroup
        AssignGlobalAdministrator = $true
        RoleAssignmentScope       = '/'
        ConditionalAccessCount    = @($policies).Count
        PatchConditionalAccess    = [bool]$Config.PatchCAPolicies
        CAPoliciesToChange        = @($toPatch | Select-Object id,displayName,state)
        CAPoliciesAlreadyExcluded = @($alreadyExcluded | Select-Object id,displayName,state)
        OutputFolder              = $outputFolder
        HandoffPath               = Join-Path $outputFolder 'handoff.html'
        Warnings                  = $warnings
        GeneratedAt               = (Get-Date).ToString('o')
    }
    $sync.State.Plan = $plan
    return $plan
}
