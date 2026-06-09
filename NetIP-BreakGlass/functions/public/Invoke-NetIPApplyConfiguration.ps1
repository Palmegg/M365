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
        $tenant = Get-NetIPTenantInfo
        $output = if ($sync.State.OutputFolder) { $sync.State.OutputFolder } else { New-NetIPOutputFolder -TenantId $tenant.TenantId }
        New-Item -ItemType Directory -Force -Path $output | Out-Null

        $upn1 = ConvertTo-NetIPBreakGlassUpn -Prefix $config.UserPrefix1 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        $upn2 = ConvertTo-NetIPBreakGlassUpn -Prefix $config.UserPrefix2 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        $group = Ensure-NetIPSecurityGroup -DisplayName $config.GroupName -Description $config.GroupDescription -CreateIfMissing ([bool]$config.CreateGroup) -Apply $true
        Write-NetIPLog -Level PASS -Message "Gruppe håndteret: $($config.GroupName)"

        $createdPasswords = @()
        $users = @()
        foreach ($item in @(
            @{ DisplayName = $config.DisplayName1; Upn = $upn1 },
            @{ DisplayName = $config.DisplayName2; Upn = $upn2 }
        )) {
            $existing = Get-NetIPUserByUpn -UserPrincipalName $item.Upn
            if ($existing) {
                $existing | Add-Member -MemberType NoteProperty -Name EnsureStatus -Value 'AlreadyExists' -Force
                $users += $existing
                Write-NetIPLog -Level PASS -Message "Bruger findes og genbruges: $($item.Upn)"
                continue
            }
            if (-not $config.CreateUsers) {
                $users += [pscustomobject]@{ id=''; displayName=$item.DisplayName; userPrincipalName=$item.Upn; EnsureStatus='SkippedMissing' }
                Write-NetIPLog -Level WARN -Message "Bruger mangler og oprettes ikke: $($item.Upn)"
                continue
            }
            $password = New-NetIPRandomPassword
            $user = New-NetIPBreakGlassUser -DisplayName $item.DisplayName -UserPrincipalName $item.Upn -Password $password
            $users += $user
            $createdPasswords += [pscustomobject]@{ UserPrincipalName = $item.Upn; Password = $password }
            Write-NetIPLog -Level PASS -Message "Bruger oprettet: $($item.Upn)"
        }

        $membership = @()
        if ($config.AddUsersToGroup) {
            foreach ($user in $users | Where-Object { $_.id }) {
                $membership += Ensure-NetIPGroupMember -Group $group -User $user -Apply $true
            }
        }
        else {
            $membership += [pscustomobject]@{ Status='Skipped'; Detail='Gruppemedlemskab er fravalgt.' }
        }

        $policies = @(Get-NetIPConditionalAccessPolicies)
        $backupPath = ''
        $caResults = @()
        $alreadyExcluded = @()
        if ($group -and $group.id) {
            foreach ($policy in $policies) {
                $excludeGroups = @(Get-NetIPObjectPropertyValue -InputObject (Get-NetIPObjectPropertyValue -InputObject (Get-NetIPObjectPropertyValue -InputObject $policy -Name 'conditions') -Name 'users') -Name 'excludeGroups')
                if ($excludeGroups -contains $group.id) { $alreadyExcluded += [pscustomobject]@{ Policy=$policy.displayName; PolicyId=$policy.id; Status='AlreadyExcluded' } }
            }
        }
        if ($config.PatchCAPolicies -and $group -and $group.id) {
            $backupPath = Backup-NetIPConditionalAccessPolicies -Policies $policies -OutputFolder $output
            $caResults = Add-NetIPGroupExclusionToCAPolicies -Policies $policies -GroupId $group.id -Apply $true
        }

        $changed = @($caResults | Where-Object Status -eq 'Patched')
        $failed = @($caResults | Where-Object Status -eq 'Failed')
        $result = [pscustomobject]@{
            TenantDisplayName = $tenant.TenantDisplayName
            TenantId = $tenant.TenantId
            Timestamp = (Get-Date).ToString('o')
            Operator = $sync.State.GraphAccount
            OnMicrosoftDomain = $tenant.OnMicrosoftDomain
            Account1 = [pscustomobject]@{ DisplayName=$config.DisplayName1; UserPrincipalName=$upn1; Status=($users[0].EnsureStatus) }
            Account2 = [pscustomobject]@{ DisplayName=$config.DisplayName2; UserPrincipalName=$upn2; Status=($users[1].EnsureStatus) }
            Group = [pscustomobject]@{ DisplayName=$group.displayName; Id=$group.id; Status=$group.EnsureStatus }
            GroupMembership = $membership
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
            Show-NetIPCreatedPasswordsOnce -CreatedPasswords $createdPasswords
        }
        $sync.Form.Dispatcher.BeginInvoke([action]{
            $sync.WPFOutputFolder.Text = $sync.State.OutputFolder
            $sync.WPFHandoffPath.Text = $sync.State.HandoffPath
            Invoke-NetIPWPFButton -Name 'WPFStepHandoff'
        }) | Out-Null
        Write-NetIPStatus -Message 'Konfiguration er anvendt, og handoff er genereret.'
    }
}
