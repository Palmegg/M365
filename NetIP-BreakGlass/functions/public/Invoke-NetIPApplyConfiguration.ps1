function Invoke-NetIPApplyConfiguration {
    [CmdletBinding()]
    param()

    if (-not $sync.State.Plan) {
        [System.Windows.MessageBox]::Show('Generér en plan før du udfører ændringer.', $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }
    $config = Get-NetIPConfigFromUI
    $plan = $sync.State.Plan
    $summary = @"
Følgende udføres:

Brugere:
- $($plan.Account1UPN): $($plan.Account1Status)
- $($plan.Account2UPN): $($plan.Account2Status)

Eksisterende passwords ændres ikke.
Gruppe: $($plan.GroupName) / $($plan.GroupStatus)
Medlemskab opdateres: $($plan.AddAccountsToGroup)
Global Administrator tildeles direkte til begge konti: Ja
Conditional Access policies patches: $($plan.PatchConditionalAccess)
Antal policies der patches: $(@($plan.CAPoliciesToChange).Count)

CA policies bliver backuppet før patching.
Genererede passwords vises én gang og gemmes ikke.

Vil du fortsætte?
"@
    $answer = [System.Windows.MessageBox]::Show($summary, $sync.App.Name, 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }

    Invoke-NetIPRunspace -ArgumentList @($config) -ScriptBlock {
        param($config)
        Write-NetIPStatus -Busy -Message 'Anvender konfiguration...'
        Write-NetIPLog -Message 'Step 1/8: Henter tenant og klargør outputmappe...'
        $tenant = Get-NetIPTenantInfo
        $output = if ($sync.State.OutputFolder) { $sync.State.OutputFolder } else { New-NetIPOutputFolder -TenantId $tenant.TenantId }
        New-Item -ItemType Directory -Force -Path $output | Out-Null

        $upn1 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix1 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        $upn2 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix2 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        Write-NetIPLog -Message 'Step 2/8: Sikrer CA-exclude gruppe...'
        $group = Ensure-NetIPSecurityGroup -DisplayName $config.GroupName -Description $config.GroupDescription -CreateIfMissing ([bool]$config.CreateGroup) -Apply $true
        Write-NetIPLog -Level PASS -Message "Gruppe håndteret: $($config.GroupName)"

        Write-NetIPLog -Message 'Step 3/8: Sikrer break-glass brugere...'
        $createdPasswords = @()
        $users = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @(
            @{ DisplayName = $config.DisplayName1; Upn = $upn1 },
            @{ DisplayName = $config.DisplayName2; Upn = $upn2 }
        )) {
            $existing = Get-NetIPUserByUpn -UserPrincipalName $item.Upn
            if ($existing) {
                $existing | Add-Member -MemberType NoteProperty -Name EnsureStatus -Value 'AlreadyExists' -Force
                $users.Add($existing)
                Write-NetIPLog -Level PASS -Message "Bruger findes og genbruges: $($item.Upn)"
                continue
            }
            if (-not $config.CreateUsers) {
                $users.Add([pscustomobject]@{ id=''; displayName=$item.DisplayName; userPrincipalName=$item.Upn; EnsureStatus='SkippedMissing' })
                Write-NetIPLog -Level WARN -Message "Bruger mangler og oprettes ikke: $($item.Upn)"
                continue
            }
            $password = New-NetIPRandomPassword
            $user = New-BreakGlassUser -DisplayName $item.DisplayName -UserPrincipalName $item.Upn -Password $password
            $users.Add($user)
            $createdPasswords += [pscustomobject]@{ UserPrincipalName = $item.Upn; Password = $password }
            Write-NetIPLog -Level PASS -Message "Bruger oprettet: $($item.Upn)"
        }

        Write-NetIPLog -Message 'Step 4/8: Sikrer gruppemedlemskab...'
        $membership = @()
        if ($config.AddUsersToGroup) {
            foreach ($user in $users | Where-Object { Get-NetIPObjectPropertyValue -InputObject $_ -Name 'id' }) {
                $membership += Ensure-NetIPGroupMember -Group $group -User $user -Apply $true
            }
        }
        else {
            $membership += [pscustomobject]@{ Status='Skipped'; Detail='Gruppemedlemskab er fravalgt.' }
        }

        Write-NetIPLog -Message 'Step 5/8: Sikrer direkte Global Administrator rolle...'
        $roleDefinition = Get-NetIPGlobalAdministratorRoleDefinition
        $roleAssignments = @()
        foreach ($user in $users | Where-Object { Get-NetIPObjectPropertyValue -InputObject $_ -Name 'id' }) {
            $roleAssignments += Ensure-NetIPGlobalAdministratorAssignment -User $user -RoleDefinition $roleDefinition -Apply $true
        }

        Write-NetIPLog -Message 'Step 6/8: Henter Conditional Access policies...'
        $policies = @(Get-NetIPConditionalAccessPolicies)
        $backupPath = ''
        $caResults = @()
        $alreadyExcluded = @()
        $groupId = [string](Get-NetIPObjectPropertyValue -InputObject $group -Name 'id')
        $groupDisplayName = [string](Get-NetIPObjectPropertyValue -InputObject $group -Name 'displayName')
        $groupStatus = [string](Get-NetIPObjectPropertyValue -InputObject $group -Name 'EnsureStatus')
        if ($group -and $groupId) {
            foreach ($policy in $policies) {
                $excludeGroups = @(Get-NetIPObjectPropertyValue -InputObject (Get-NetIPObjectPropertyValue -InputObject (Get-NetIPObjectPropertyValue -InputObject $policy -Name 'conditions') -Name 'users') -Name 'excludeGroups')
                if ($excludeGroups -contains $groupId) {
                    $alreadyExcluded += [pscustomobject]@{
                        Policy = [string](Get-NetIPObjectPropertyValue -InputObject $policy -Name 'displayName')
                        PolicyId = [string](Get-NetIPObjectPropertyValue -InputObject $policy -Name 'id')
                        Status = 'AlreadyExcluded'
                    }
                }
            }
        }
        if ($config.PatchCAPolicies -and $group -and $groupId) {
            Write-NetIPLog -Message 'Step 7/8: Backupper og opdaterer Conditional Access policies...'
            $backupPath = Backup-NetIPConditionalAccessPolicies -Policies $policies -OutputFolder $output
            $caResults = Add-NetIPGroupExclusionToCAPolicies -Policies $policies -GroupId $groupId -Apply $true
        }
        else {
            Write-NetIPLog -Message 'Step 7/8: Conditional Access patching er fravalgt.'
        }

        Write-NetIPLog -Message 'Step 8/8: Gemmer resultat og genererer handoff...'
        $changed = @($caResults | Where-Object Status -eq 'Patched')
        $failed = @($caResults | Where-Object Status -eq 'Failed')
        $account1Status = [string](Get-NetIPObjectPropertyValue -InputObject $users[0] -Name 'EnsureStatus')
        $account2Status = [string](Get-NetIPObjectPropertyValue -InputObject $users[1] -Name 'EnsureStatus')
        $result = [pscustomobject]@{
            TenantDisplayName = $tenant.TenantDisplayName
            TenantId = $tenant.TenantId
            Timestamp = (Get-Date).ToString('o')
            Operator = $sync.State.GraphAccount
            OnMicrosoftDomain = $tenant.OnMicrosoftDomain
            Account1 = [pscustomobject]@{ DisplayName=$config.DisplayName1; UserPrincipalName=$upn1; Status=$account1Status }
            Account2 = [pscustomobject]@{ DisplayName=$config.DisplayName2; UserPrincipalName=$upn2; Status=$account2Status }
            Group = [pscustomobject]@{ DisplayName=$groupDisplayName; Id=$groupId; Status=$groupStatus }
            GroupMembership = $membership
            RoleAssignments = $roleAssignments
            CAExclusionsEnabled = [bool]$config.PatchCAPolicies
            CAPoliciesChangedCount = $changed.Count
            CAPoliciesChanged = $changed
            CAPoliciesAlreadyExcluded = $alreadyExcluded
            CAPoliciesFailed = $failed
            CABackupPath = $backupPath
            Warnings = @($sync.State.Warnings)
        }
        $sync.State.Result = $result
        Save-NetIPResultJson -Result $result -OutputFolder $output | Out-Null
        $handoff = New-NetIPHandoffHtml -Result $result -OutputFolder $output
        $sync.State.HandoffPath = $handoff
        if ($createdPasswords.Count -gt 0) {
            $sync.State.CreatedPasswords = $createdPasswords
            Write-NetIPLog -Message 'Viser midlertidige adgangskoder i separat vindue. Gem dem sikkert; de bliver ikke skrevet til log eller rapport.'
            Show-NetIPCreatedPasswordsOnce -CreatedPasswords $createdPasswords
        }
        $sync.Form.Dispatcher.Invoke([System.Action]{
            $sync.WPFOutputFolder.Text = $sync.State.OutputFolder
            $sync.WPFHandoffPath.Text = $sync.State.HandoffPath
            Invoke-NetIPWPFButton -Name 'WPFStepHandoff'
        })
        Write-NetIPStatus -Message 'Konfiguration er anvendt, og handoff er genereret.'
    }
}
