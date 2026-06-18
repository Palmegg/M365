function New-EbgPlanObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Config,
        [AllowNull()] $Discovery = $null
    )

    $tenant = Get-EbgTenantInfo
    $upn1 = ConvertTo-BreakGlassUpn -Prefix $Config.UserPrefix1 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
    $upn2 = ConvertTo-BreakGlassUpn -Prefix $Config.UserPrefix2 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
    $user1 = if ($Discovery) { $Discovery.User1 } else { Get-EbgUserByUpn -UserPrincipalName $upn1 }
    $user2 = if ($Discovery) { $Discovery.User2 } else { Get-EbgUserByUpn -UserPrincipalName $upn2 }
    $group = if ($Discovery) { $Discovery.Group } else { Get-EbgGroupByDisplayName -DisplayName $Config.GroupName }
    $policies = if ($Discovery) { @($Discovery.CAPolicies) } else { @(Get-EbgConditionalAccessPolicies) }
    $authorizationPolicy = Get-EbgAuthorizationPolicy
    $adminSSPREnabled = [bool](Get-EbgObjectPropertyValue -InputObject $authorizationPolicy -Name 'allowedToUseSSPR')

    $alreadyExcluded = @()
    $toPatch = @()
    if ($group -and $group.id) {
        foreach ($policy in $policies) {
            $excludeGroups = @(Get-EbgObjectPropertyValue -InputObject (Get-EbgObjectPropertyValue -InputObject (Get-EbgObjectPropertyValue -InputObject $policy -Name 'conditions') -Name 'users') -Name 'excludeGroups')
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
    if ($Config.DisableAdminSSPR) { $warnings += 'Administrator-SSPR deaktiveres tenant-wide og kan tage op til 60 minutter at slå igennem.' }
    $warnings += 'Phase 1 opretter Temporary Access Pass for begge konti: one-time use = Yes, duration = 2 hours.'
    $warnings += 'Phase 1b kræver manuel registrering af to FIDO2 security keys pr. konto.'
    $warnings += 'Phase 2 opretter/opdaterer BreakGlass-FIDO2 authentication strength og en dedikeret CA-policy som disabled.'
    if ($Config.PatchCAPolicies) { $warnings += 'Eksisterende Conditional Access-politikker ændres. Backup oprettes før ændringer.' }
    if (@($Config.AAGUIDs).Count -lt 1) { $warnings += 'AAGUIDs hentes normalt automatisk i Phase 2 efter FIDO2 keys er registreret.' }

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
        DisableAdminSSPR          = [bool]$Config.DisableAdminSSPR
        CurrentAdminSSPREnabled   = $adminSSPREnabled
        PlannedAdminSSPRStatus    = if ($Config.DisableAdminSSPR) { if ($adminSSPREnabled) { 'Deaktiveres' } else { 'Allerede deaktiveret' } } else { 'Uændret' }
        AuthenticationStrengthName = $Config.AuthenticationStrengthName
        AuthenticationStrengthAAGUIDs = @($Config.AAGUIDs)
        TemporaryAccessPassStatus    = 'Phase 1: oprettes for begge konti, one-time use, 2 timer'
        AuthenticationStrengthStatus = if (@($Config.AAGUIDs).Count -gt 0) { 'Phase 2: oprettes/opdateres med angivne + fundne AAGUIDs' } else { 'Phase 2: oprettes/opdateres efter automatisk AAGUID refresh' }
        BreakGlassCAPolicyName    = $Config.BreakGlassCAPolicyName
        BreakGlassCAPolicyStatus  = 'Phase 2: oprettes disabled og tildeles direkte til de 2 konti'
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