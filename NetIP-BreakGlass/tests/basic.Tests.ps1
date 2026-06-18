Describe 'NetIP-BreakGlass basic functions' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        Get-ChildItem -LiteralPath (Join-Path $root 'functions') -Recurse -File -Filter '*.ps1' | ForEach-Object { . $_.FullName }
        $script:sync = [Hashtable]::Synchronized(@{})
        $script:sync.App = @{ Mock = $true; OutputRoot = Join-Path $root 'Output' }
        $script:sync.State = [Hashtable]::Synchronized(@{ OnMicrosoftDomain = 'contoso.onmicrosoft.com'; OutputFolder = ''; Warnings = @() })
        $script:sync.configs = @{
            defaults = [pscustomobject]@{}
            appsettings = [pscustomobject]@{ groupName = 'CA-BreakGlass-Exclude'; groupDescription = 'Security group used to exclude dedicated break-glass accounts from existing Conditional Access policies.' }
        }
    }

    It 'builds UPN from prefix' {
        $actual = ConvertTo-BreakGlassUpn -Prefix 'horse.unit' -OnMicrosoftDomain 'contoso.onmicrosoft.com'
        if ($actual -ne 'horse.unit@contoso.onmicrosoft.com') { throw "Unexpected UPN: $actual" }
    }

    It 'creates neutral UPN prefixes from display names' {
        $actual = ConvertTo-NetIPNeutralUserPrefix -DisplayName 'Plane Model'
        if ($actual -ne 'plane.model') { throw "Unexpected neutral prefix: $actual" }
    }

    It 'generates long password' {
        $password = New-NetIPRandomPassword
        if ($password.Length -lt 24) { throw 'Password is too short.' }
    }

    It 'plans expected accounts' {
        $config = @{
            UserPrefix1 = 'horse.unit'; UserPrefix2 = 'master.player'
            DisplayName1 = 'Horse Unit'; DisplayName2 = 'Master Player'
            GroupName = 'CA-BreakGlass-Exclude'; CreateUsers = $true; CreateGroup = $true
            AddUsersToGroup = $true; DisableAdminSSPR = $true; PatchCAPolicies = $false
        }
        $plan = New-NetIPPlanObject -Config $config
        if ($plan.Account1UPN -ne 'horse.unit@contoso.onmicrosoft.com') { throw "Unexpected planned UPN: $($plan.Account1UPN)" }
        if ($plan.PlannedAdminSSPRStatus -ne 'Deaktiveres') { throw "Unexpected Admin SSPR plan: $($plan.PlannedAdminSSPRStatus)" }
    }

    It 'preserves existing CA exclusions in mock patch plan' {
        $policies = @(Get-NetIPConditionalAccessPolicies)
        $result = Add-NetIPGroupExclusionToCAPolicies -Policies $policies -GroupId 'mock-ca-exclude-group' -Apply $false
        $count = @($result | Where-Object Status -eq 'PlannedPatch').Count
        if ($count -ne 3) { throw "Expected 3 planned patches, got $count" }
    }

    It 'handles group membership with Graph hashtable objects' {
        $group = @{ id = 'mock-ca-exclude-group'; displayName = 'CA-BreakGlass-Exclude' }
        $user = @{ id = 'mock-user-2'; userPrincipalName = 'svc_ea_02@contoso.onmicrosoft.com' }
        $result = Ensure-NetIPGroupMember -Group $group -User $user -Apply $true
        if ($result.Status -ne 'Added') { throw "Unexpected membership status: $($result.Status)" }
        if ($result.UserPrincipalName -ne 'svc_ea_02@contoso.onmicrosoft.com') { throw "Unexpected membership user: $($result.UserPrincipalName)" }
    }

    It 'plans Global Administrator assignment' {
        $config = @{
            UserPrefix1 = 'horse.unit'; UserPrefix2 = 'master.player'
            DisplayName1 = 'Horse Unit'; DisplayName2 = 'Master Player'
            GroupName = 'CA-BreakGlass-Exclude'; CreateUsers = $true; CreateGroup = $true
            AddUsersToGroup = $true; DisableAdminSSPR = $true; PatchCAPolicies = $false
        }
        $plan = New-NetIPPlanObject -Config $config
        if (-not $plan.AssignGlobalAdministrator) { throw 'Plan does not include Global Administrator assignment.' }
        if ($plan.RoleAssignmentScope -ne '/') { throw "Unexpected role assignment scope: $($plan.RoleAssignmentScope)" }
    }

    It 'handles Global Administrator role assignment in mock mode' {
        $role = Get-NetIPGlobalAdministratorRoleDefinition
        $user = @{ id = 'mock-user-2'; userPrincipalName = 'svc_ea_02@contoso.onmicrosoft.com' }
        $result = Ensure-NetIPGlobalAdministratorAssignment -User $user -RoleDefinition $role -Apply $true
        if ($result.Status -ne 'Assigned') { throw "Unexpected role assignment status: $($result.Status)" }
        if ($result.Role -ne 'Global Administrator') { throw "Unexpected role assignment role: $($result.Role)" }
    }

    It 'handles administrator SSPR disable in mock mode' {
        $result = Set-NetIPAdminSSPRDisabled -Apply $true
        if ($result.Status -ne 'Disabled') { throw "Unexpected Admin SSPR status: $($result.Status)" }
        if ($result.DesiredValue -ne $false) { throw "Unexpected Admin SSPR desired value: $($result.DesiredValue)" }
    }

    It 'reads properties case-insensitively without numeric index binding' {
        $user = @{ id = 'mock-user-3'; userPrincipalName = 'svc_ea_03@contoso.onmicrosoft.com' }
        $upn = Get-NetIPObjectPropertyValue -InputObject $user -Name 'UserPrincipalName'
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
            GroupMembership = @(@{ UserPrincipalName = 'svc_ea_01@contoso.onmicrosoft.com'; Group = 'CA-BreakGlass-Exclude'; Status = 'Added' })
            RoleAssignments = @(@{ UserPrincipalName = 'svc_ea_01@contoso.onmicrosoft.com'; Role = 'Global Administrator'; Scope = '/'; Status = 'Assigned' })
            AdminSSPR = @{ Setting = 'allowedToUseSSPR'; PreviousValue = $true; DesiredValue = $false; Status = 'Disabled'; Detail = 'Policy changes can take up to 60 minutes to take effect.' }
            CAExclusionsEnabled = $false
            CAPoliciesChangedCount = 0
            CABackupPath = ''
            CAPoliciesChanged = @()
            CAPoliciesAlreadyExcluded = @()
            CAPoliciesFailed = @()
            Warnings = @()
        }
        $path = New-NetIPHandoffHtml -Result $result -OutputFolder $output
        if (-not (Test-Path -LiteralPath $path)) { throw 'Handoff file was not created.' }
        $html = Get-Content -LiteralPath $path -Raw
        if ($html -notmatch 'svc_ea_01@contoso.onmicrosoft.com') { throw 'Handoff missing account UPN.' }
        if ($html -notmatch 'Global Administrator') { throw 'Handoff missing Global Administrator assignment.' }
        if ($html -notmatch 'allowedToUseSSPR') { throw 'Handoff missing Admin SSPR result.' }
    }
}
