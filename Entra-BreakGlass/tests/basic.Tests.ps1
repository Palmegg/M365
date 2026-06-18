Describe 'Ebg-BreakGlass basic functions' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        Get-ChildItem -LiteralPath (Join-Path $root 'functions') -Recurse -File -Filter '*.ps1' | ForEach-Object { . $_.FullName }
        $script:sync = [Hashtable]::Synchronized(@{})
        $script:sync.App = @{ Mock = $true; OutputRoot = Join-Path $root 'Output' }
        $script:sync.State = [Hashtable]::Synchronized(@{ OnMicrosoftDomain = 'contoso.onmicrosoft.com'; OutputFolder = ''; Warnings = @() })
        $script:sync.configs = @{
            defaults = [pscustomobject]@{}
            appsettings = [pscustomobject]@{
                groupName = 'CA-BreakGlass-Exclude'
                groupDescription = 'Security group used to exclude dedicated break-glass accounts from existing Conditional Access policies.'
                regularSSPRGroupName = 'SG-SSPR-AllUsers-Except-BreakGlass'
                regularSSPRGroupDescription = 'Dynamic security group for regular SSPR targeting. Includes enabled member users except the two dedicated break-glass accounts.'
                authenticationStrengthName = 'BreakGlass-FIDO2'
                authenticationStrengthDescription = 'Requires passkeys (FIDO2) from approved attested security key AAGUIDs for break-glass accounts.'
                breakGlassCAPolicyName = '[CA999] IdentityProtection-AnyApp-AnyPlatform-BreakGlass-FIDO2'
            }
        }
    }

    It 'builds UPN from prefix' {
        $actual = ConvertTo-BreakGlassUpn -Prefix 'horse.unit' -OnMicrosoftDomain 'contoso.onmicrosoft.com'
        if ($actual -ne 'horse.unit@contoso.onmicrosoft.com') { throw "Unexpected UPN: $actual" }
    }

    It 'creates neutral UPN prefixes from display names' {
        $actual = ConvertTo-EbgNeutralUserPrefix -DisplayName 'Plane Model'
        if ($actual -ne 'plane.model') { throw "Unexpected neutral prefix: $actual" }
    }

    It 'extracts AAGUIDs from free text' {
        $actual = @(ConvertFrom-EbgAAGUIDText -Text 'Key: A4E9FC6D-4CBE-4758-B8BA-37598BB5BBAA, duplicate a4e9fc6d-4cbe-4758-b8ba-37598bb5bbaa')
        if ($actual.Count -ne 1) { throw "Unexpected AAGUID count: $($actual.Count)" }
        if ($actual[0] -ne 'a4e9fc6d-4cbe-4758-b8ba-37598bb5bbaa') { throw "Unexpected AAGUID: $($actual[0])" }
    }

    It 'uses shortened wizard flow when resuming Phase 2' {
        $sync.State.StartMode = 'Phase2'
        $steps = @(Get-EbgWorkflowSteps)
        if ($steps -contains 'Discovery') { throw 'Resume flow should not include Discovery.' }
        if ($steps -contains 'Config') { throw 'Resume flow should not include Config.' }
        if ($steps -contains 'Plan') { throw 'Resume flow should not include Plan.' }
        if ($steps -contains 'Apply') { throw 'Resume flow should not include Phase 1a Apply.' }
        if ($steps -contains 'ManualFido') { throw 'Resume flow should not include ManualFido.' }
        if (($steps -join ',') -ne 'Welcome,Connect,Phase2,Handoff') { throw "Unexpected resume steps: $($steps -join ',')" }
        $sync.State.StartMode = 'Phase1'
    }

    It 'generates long password' {
        $password = New-EbgRandomPassword
        if ($password.Length -lt 24) { throw 'Password is too short.' }
    }

    It 'plans expected accounts' {
        $config = @{
            UserPrefix1 = 'horse.unit'; UserPrefix2 = 'master.player'
            DisplayName1 = 'Horse Unit'; DisplayName2 = 'Master Player'
            GroupName = 'CA-BreakGlass-Exclude'; CreateUsers = $true; CreateGroup = $true
            AddUsersToGroup = $true; DisableAdminSSPR = $true; PatchCAPolicies = $false
            CreateRegularSSPRScopeGroup = $true; RegularSSPRGroupName = 'SG-SSPR-AllUsers-Except-BreakGlass'; RegularSSPRGroupDescription = 'Test'
            CreateAuthenticationStrength = $true; CreateBreakGlassCAPolicy = $true; EnableBreakGlassCAPolicy = $false
            AuthenticationStrengthName = 'BreakGlass-FIDO2'; BreakGlassCAPolicyName = '[CA999] IdentityProtection-AnyApp-AnyPlatform-BreakGlass-FIDO2'
            AAGUIDs = @('a4e9fc6d-4cbe-4758-b8ba-37598bb5bbaa')
        }
        $plan = New-EbgPlanObject -Config $config
        if ($plan.Account1UPN -ne 'horse.unit@contoso.onmicrosoft.com') { throw "Unexpected planned UPN: $($plan.Account1UPN)" }
        if ($plan.PlannedAdminSSPRStatus -ne 'Deaktiveres') { throw "Unexpected Admin SSPR plan: $($plan.PlannedAdminSSPRStatus)" }
        if ($plan.TemporaryAccessPassStatus -ne 'Phase 1: oprettes for begge konti, genanvendelig i 2 timer') { throw "Unexpected TAP plan: $($plan.TemporaryAccessPassStatus)" }
        if ($plan.Fido2AuthenticationMethodPolicyStatus -ne 'Phase 1: enables FIDO2/passkey for CA-BreakGlass-Exclude') { throw "Unexpected FIDO2 method policy plan: $($plan.Fido2AuthenticationMethodPolicyStatus)" }
        if ($plan.RegistrationCampaignStatus -ne 'Phase 1: excludes CA-BreakGlass-Exclude from authentication methods registration campaign') { throw "Unexpected registration campaign plan: $($plan.RegistrationCampaignStatus)" }
        if ($plan.RegularSSPRGroupName -ne 'SG-SSPR-AllUsers-Except-BreakGlass') { throw "Unexpected regular SSPR group: $($plan.RegularSSPRGroupName)" }
        if ($plan.AuthenticationStrengthStatus -ne 'Phase 2: oprettes/opdateres med angivne + fundne AAGUIDs') { throw "Unexpected auth strength plan: $($plan.AuthenticationStrengthStatus)" }
        if ($plan.BreakGlassCAPolicyStatus -ne 'Phase 2: oprettes disabled og tildeles direkte til de 2 konti') { throw "Unexpected BG CA plan: $($plan.BreakGlassCAPolicyStatus)" }
    }

    It 'preserves existing CA exclusions in mock patch plan' {
        $policies = @(Get-EbgConditionalAccessPolicies)
        $result = Add-EbgGroupExclusionToCAPolicies -Policies $policies -GroupId 'mock-ca-exclude-group' -Apply $false
        $count = @($result | Where-Object Status -eq 'PlannedPatch').Count
        if ($count -ne 3) { throw "Expected 3 planned patches, got $count" }
    }

    It 'normalizes Conditional Access users patch schema' {
        $users = [pscustomobject]@{
            includeUsers = @()
            includeGroups = @('group-a')
            excludeGroups = @('group-b')
            includeGuestsOrExternalUsers = [pscustomobject]@{
                guestOrExternalUserTypes = 'internalGuest,b2bCollaborationGuest'
            }
            '@odata.type' = '#microsoft.graph.conditionalAccessUsers'
        }
        $patch = ConvertTo-EbgConditionalAccessUsersPatch -Users $users -GroupId 'mock-ca-exclude-group'
        if ($patch.Contains('@odata.type')) { throw 'Patch should not contain @odata.type.' }
        if (-not (@($patch.excludeGroups) -contains 'mock-ca-exclude-group')) { throw 'Patch missing new exclude group.' }
        if (-not $patch.Contains('includeGuestsOrExternalUsers')) { throw 'Patch should preserve guest/external users condition.' }
    }

    It 'handles group membership with Graph hashtable objects' {
        $group = @{ id = 'mock-ca-exclude-group'; displayName = 'CA-BreakGlass-Exclude' }
        $user = @{ id = 'mock-user-2'; userPrincipalName = 'svc_ea_02@contoso.onmicrosoft.com' }
        $result = Ensure-EbgGroupMember -Group $group -User $user -Apply $true
        if ($result.Status -ne 'Added') { throw "Unexpected membership status: $($result.Status)" }
        if ($result.UserPrincipalName -ne 'svc_ea_02@contoso.onmicrosoft.com') { throw "Unexpected membership user: $($result.UserPrincipalName)" }
    }

    It 'plans Global Administrator assignment' {
        $config = @{
            UserPrefix1 = 'horse.unit'; UserPrefix2 = 'master.player'
            DisplayName1 = 'Horse Unit'; DisplayName2 = 'Master Player'
            GroupName = 'CA-BreakGlass-Exclude'; CreateUsers = $true; CreateGroup = $true
            AddUsersToGroup = $true; DisableAdminSSPR = $true; PatchCAPolicies = $false
            CreateRegularSSPRScopeGroup = $true; RegularSSPRGroupName = 'SG-SSPR-AllUsers-Except-BreakGlass'; RegularSSPRGroupDescription = 'Test'
            CreateAuthenticationStrength = $false; CreateBreakGlassCAPolicy = $false; EnableBreakGlassCAPolicy = $false
            AuthenticationStrengthName = 'BreakGlass-FIDO2'; BreakGlassCAPolicyName = '[CA999] IdentityProtection-AnyApp-AnyPlatform-BreakGlass-FIDO2'
            AAGUIDs = @()
        }
        $plan = New-EbgPlanObject -Config $config
        if (-not $plan.AssignGlobalAdministrator) { throw 'Plan does not include Global Administrator assignment.' }
        if ($plan.RoleAssignmentScope -ne '/') { throw "Unexpected role assignment scope: $($plan.RoleAssignmentScope)" }
    }

    It 'handles Global Administrator role assignment in mock mode' {
        $role = Get-EbgGlobalAdministratorRoleDefinition
        $user = @{ id = 'mock-user-2'; userPrincipalName = 'svc_ea_02@contoso.onmicrosoft.com' }
        $result = Ensure-EbgGlobalAdministratorAssignment -User $user -RoleDefinition $role -Apply $true
        if ($result.Status -ne 'Assigned') { throw "Unexpected role assignment status: $($result.Status)" }
        if ($result.Role -ne 'Global Administrator') { throw "Unexpected role assignment role: $($result.Role)" }
    }

    It 'handles administrator SSPR disable in mock mode' {
        $result = Set-EbgAdminSSPRDisabled -Apply $true
        if ($result.Status -ne 'Disabled') { throw "Unexpected Admin SSPR status: $($result.Status)" }
        if ($result.DesiredValue -ne $false) { throw "Unexpected Admin SSPR desired value: $($result.DesiredValue)" }
    }

    It 'creates regular SSPR dynamic group rule in mock mode' {
        $users = @(
            @{ id = '11111111-1111-1111-1111-111111111111'; userPrincipalName = 'account1@contoso.onmicrosoft.com' },
            @{ id = '22222222-2222-2222-2222-222222222222'; userPrincipalName = 'account2@contoso.onmicrosoft.com' }
        )
        $result = Ensure-EbgRegularSSPRScopeGroup -DisplayName 'SG-SSPR-AllUsers-Except-BreakGlass' -Description 'Test' -BreakGlassUsers $users -CreateOrUpdate $true -Apply $true
        if ($result.Status -ne 'CreatedOrUpdated') { throw "Unexpected regular SSPR group status: $($result.Status)" }
        if ($result.MembershipRule -notmatch '11111111-1111-1111-1111-111111111111') { throw 'Rule missing first account object ID.' }
        if ($result.MembershipRule -notmatch '22222222-2222-2222-2222-222222222222') { throw 'Rule missing second account object ID.' }
        if ($result.MembershipRule -notmatch 'user.objectId -notIn') { throw "Unexpected dynamic rule: $($result.MembershipRule)" }
    }

    It 'handles authentication strength and dedicated CA policy in mock mode' {
        $strength = Ensure-EbgAuthenticationStrength -DisplayName 'BreakGlass-FIDO2' -Description 'Test' -AllowedAAGUIDs @('a4e9fc6d-4cbe-4758-b8ba-37598bb5bbaa') -Apply $true
        if ($strength.Status -ne 'Created') { throw "Unexpected auth strength status: $($strength.Status)" }
        $policy = Ensure-EbgBreakGlassCAPolicy -DisplayName '[CA999] IdentityProtection-AnyApp-AnyPlatform-BreakGlass-FIDO2' -UserIds @('mock-user-1','mock-user-2') -AuthenticationStrengthId $strength.id -Enabled $false -Apply $true
        if ($policy.state -ne 'disabled') { throw "Unexpected CA policy state: $($policy.state)" }
    }

    It 'creates Temporary Access Pass in mock mode' {
        $user = @{ id = 'mock-user-2'; userPrincipalName = 'svc_ea_02@contoso.onmicrosoft.com' }
        $tap = New-EbgTemporaryAccessPass -User $user -LifetimeInMinutes 120 -IsUsableOnce $false -Apply $true
        if ($tap.Status -ne 'Created') { throw "Unexpected TAP status: $($tap.Status)" }
        if ($tap.isUsableOnce -ne $false) { throw "Unexpected TAP one-time setting: $($tap.isUsableOnce)" }
        if ($tap.lifetimeInMinutes -ne 120) { throw "Unexpected TAP lifetime: $($tap.lifetimeInMinutes)" }
    }

    It 'ensures FIDO2/passkey authentication method policy in mock mode' {
        $group = @{ id = 'mock-ca-exclude-group'; displayName = 'CA-BreakGlass-Exclude' }
        $result = Ensure-EbgFido2AuthenticationMethodPolicy -Group $group -Apply $true
        if ($result.Status -ne 'Updated') { throw "Unexpected FIDO2 method policy status: $($result.Status)" }
        if ($result.state -ne 'enabled') { throw "Unexpected FIDO2 method policy state: $($result.state)" }
        if ($result.TargetGroupId -ne 'mock-ca-exclude-group') { throw "Unexpected FIDO2 method policy target: $($result.TargetGroupId)" }
    }

    It 'excludes group from authentication methods registration campaign in mock mode' {
        $group = @{ id = 'mock-ca-exclude-group'; displayName = 'CA-BreakGlass-Exclude' }
        $result = Ensure-EbgRegistrationCampaignExclusion -Group $group -Apply $true
        if ($result.Status -ne 'Excluded') { throw "Unexpected registration campaign status: $($result.Status)" }
        if ($result.TargetGroupId -ne 'mock-ca-exclude-group') { throw "Unexpected registration campaign target: $($result.TargetGroupId)" }
    }

    It 'reads properties case-insensitively without numeric index binding' {
        $user = @{ id = 'mock-user-3'; userPrincipalName = 'svc_ea_03@contoso.onmicrosoft.com' }
        $upn = Get-EbgObjectPropertyValue -InputObject $user -Name 'UserPrincipalName'
        if ($upn -ne 'svc_ea_03@contoso.onmicrosoft.com') { throw "Unexpected UPN lookup: $upn" }
    }

    It 'generates handoff from nested hashtables' {
        $output = Join-Path $root 'Output\pester-handoff'
        $result = [pscustomobject]@{
            TenantDisplayName = 'Contoso'
            TenantId = 'tenant-id'
            Timestamp = (Get-Date).ToString('o')
            Operator = 'operator@contoso.onmicrosoft.com'
            OnMicrosoftDomain = 'contoso.onmicrosoft.com'
            Account1 = @{ DisplayName = 'Horse Unit'; UserPrincipalName = 'svc_ea_01@contoso.onmicrosoft.com'; Status = 'Created' }
            Account2 = @{ DisplayName = 'Master Player'; UserPrincipalName = 'svc_ea_02@contoso.onmicrosoft.com'; Status = 'Created' }
            Group = @{ DisplayName = 'CA-BreakGlass-Exclude'; Id = 'group-id'; Status = 'Created' }
            Fido2AuthenticationMethodPolicy = @{ displayName = 'FIDO2/passkey authentication method policy'; state = 'enabled'; TargetGroupName = 'CA-BreakGlass-Exclude'; Status = 'Updated'; Detail = 'FIDO2/passkey enabled for group CA-BreakGlass-Exclude.' }
            RegistrationCampaign = @{ TargetGroupName = 'CA-BreakGlass-Exclude'; Status = 'Excluded'; Detail = 'Group CA-BreakGlass-Exclude is excluded from authentication methods registration campaign.' }
            RegularSSPR = @{ DisplayName = 'SG-SSPR-AllUsers-Except-BreakGlass'; Id = 'sspr-group-id'; Status = 'Created'; MembershipRule = '(user.accountEnabled -eq true)'; ManualAction = 'Set regular SSPR to Selected and choose SG-SSPR-AllUsers-Except-BreakGlass in Entra Password reset settings.' }
            GroupMembership = @(@{ UserPrincipalName = 'svc_ea_01@contoso.onmicrosoft.com'; Group = 'CA-BreakGlass-Exclude'; Status = 'Added' })
            RoleAssignments = @(@{ UserPrincipalName = 'svc_ea_01@contoso.onmicrosoft.com'; Role = 'Global Administrator'; Scope = '/'; Status = 'Assigned' })
            AdminSSPR = @{ Setting = 'allowedToUseSSPR'; PreviousValue = $true; DesiredValue = $false; Status = 'Disabled'; Detail = 'Policy changes can take up to 60 minutes to take effect.' }
            AuthenticationStrength = @{ id = 'auth-strength-id'; displayName = 'BreakGlass-FIDO2'; Status = 'Created'; allowedAAGUIDs = @('a4e9fc6d-4cbe-4758-b8ba-37598bb5bbaa') }
            BreakGlassCAPolicy = @{ id = 'ca-policy-id'; displayName = '[CA999] IdentityProtection-AnyApp-AnyPlatform-BreakGlass-FIDO2'; state = 'enabledForReportingButNotEnforced'; Status = 'Created' }
            CAExclusionsEnabled = $false
            CAPoliciesChangedCount = 0
            CABackupPath = ''
            CAPoliciesChanged = @()
            CAPoliciesAlreadyExcluded = @()
            CAPoliciesFailed = @()
            Warnings = @()
        }
        $path = New-EbgHandoffHtml -Result $result -OutputFolder $output
        if (-not (Test-Path -LiteralPath $path)) { throw 'Handoff file was not created.' }
        $html = Get-Content -LiteralPath $path -Raw
        if ($html -notmatch 'svc_ea_01@contoso.onmicrosoft.com') { throw 'Handoff missing account UPN.' }
        if ($html -notmatch 'Global Administrator') { throw 'Handoff missing Global Administrator assignment.' }
        if ($html -notmatch 'allowedToUseSSPR') { throw 'Handoff missing Admin SSPR result.' }
        if ($html -notmatch 'BreakGlass-FIDO2') { throw 'Handoff missing authentication strength result.' }
        if ($html -notmatch 'Authentication Methods registration campaign') { throw 'Handoff missing registration campaign result.' }
        if ($html -notmatch 'SG-SSPR-AllUsers-Except-BreakGlass') { throw 'Handoff missing regular SSPR scope group.' }
        if ($html -notmatch 'a4e9fc6d-4cbe-4758-b8ba-37598bb5bbaa') { throw 'Handoff missing AAGUID.' }
    }
}
