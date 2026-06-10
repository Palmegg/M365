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
        $actual = ConvertTo-NetIPBreakGlassUpn -Prefix 'BreakGlass01' -OnMicrosoftDomain 'contoso.onmicrosoft.com'
        if ($actual -ne 'BreakGlass01@contoso.onmicrosoft.com') { throw "Unexpected UPN: $actual" }
    }

    It 'generates long password' {
        $password = New-NetIPRandomPassword
        if ($password.Length -lt 24) { throw 'Password is too short.' }
    }

    It 'plans expected accounts' {
        $config = @{
            UserPrefix1 = 'BreakGlass01'; UserPrefix2 = 'BreakGlass02'
            DisplayName1 = 'BreakGlass 01'; DisplayName2 = 'BreakGlass 02'
            GroupName = 'CA-BreakGlass-Exclude'; CreateUsers = $true; CreateGroup = $true
            AddUsersToGroup = $true; PatchCAPolicies = $false
        }
        $plan = New-NetIPPlanObject -Config $config
        if ($plan.Account1UPN -ne 'BreakGlass01@contoso.onmicrosoft.com') { throw "Unexpected planned UPN: $($plan.Account1UPN)" }
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
            Account1 = @{ DisplayName = 'BreakGlass 01'; UserPrincipalName = 'svc_ea_01@contoso.onmicrosoft.com'; Status = 'Created' }
            Account2 = @{ DisplayName = 'BreakGlass 02'; UserPrincipalName = 'svc_ea_02@contoso.onmicrosoft.com'; Status = 'Created' }
            Group = @{ DisplayName = 'CA-BreakGlass-Exclude'; Id = 'group-id'; Status = 'Created' }
            GroupMembership = @(@{ UserPrincipalName = 'svc_ea_01@contoso.onmicrosoft.com'; Group = 'CA-BreakGlass-Exclude'; Status = 'Added' })
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
    }
}
