function Invoke-NetIPApplyConfiguration {
    [CmdletBinding()]
    param()

    Invoke-NetIPApplyPhase1
}

function Invoke-NetIPApplyPhase1 {
    [CmdletBinding()]
    param()

    if (-not $sync.State.Plan) {
        [System.Windows.MessageBox]::Show('Generér en plan før du udfører Phase 1.', $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }

    $config = Get-NetIPConfigFromUI
    $plan = $sync.State.Plan
    $summary = @"
Phase 1a udfører:

1. Sikrer CA-BreakGlass-Exclude security group
2. Opretter/genbruger de 2 break-glass konti
3. Tildeler direkte Global Administrator rolle
4. Deaktiverer Admin SSPR tenant-wide: $($config.DisableAdminSSPR)
5. Opretter Temporary Access Pass: one-time use = Yes, duration = 2 hours
6. Melder konti ind i exclude-gruppen
7. Ekskluderer gruppen fra eksisterende CA policies: $($config.PatchCAPolicies)

Admin SSPR kan tage op til 60 minutter før ændringen slår igennem.
Initial passwords og TAP-koder skrives ikke til almindelig log.

Vil du fortsætte?
"@
    $answer = [System.Windows.MessageBox]::Show($summary, $sync.App.Name, 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }

    Invoke-NetIPRunspace -ArgumentList @($config) -ScriptBlock {
        param($config)
        Write-NetIPStatus -Busy -Message 'Phase 1a: anvender grundopsætning...'
        Write-NetIPLog -Message 'Phase 1a step 1/10: Henter tenant og klargør outputmappe...'
        $tenant = Get-NetIPTenantInfo
        $output = if ($sync.State.OutputFolder) { $sync.State.OutputFolder } else { New-NetIPOutputFolder -TenantId $tenant.TenantId }
        $sync.State.OutputFolder = $output
        New-Item -ItemType Directory -Force -Path $output | Out-Null

        $upn1 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix1 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        $upn2 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix2 -OnMicrosoftDomain $tenant.OnMicrosoftDomain

        Write-NetIPLog -Message 'Phase 1a step 2/10: Sikrer CA-BreakGlass-Exclude security group...'
        $group = Ensure-NetIPSecurityGroup -DisplayName $config.GroupName -Description $config.GroupDescription -CreateIfMissing ([bool]$config.CreateGroup) -Apply $true
        Write-NetIPLog -Level PASS -Message "Gruppe håndteret: $($config.GroupName)"
        $groupId = [string](Get-NetIPObjectPropertyValue -InputObject $group -Name 'id')
        $groupDisplayName = [string](Get-NetIPObjectPropertyValue -InputObject $group -Name 'displayName')
        $groupStatus = [string](Get-NetIPObjectPropertyValue -InputObject $group -Name 'EnsureStatus')

        Write-NetIPLog -Message 'Phase 1a step 3/10: Sikrer de to break-glass konti...'
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

        Write-NetIPLog -Message 'Phase 1a step 4/10: Tildeler direkte Global Administrator rolle...'
        $roleDefinition = Get-NetIPGlobalAdministratorRoleDefinition
        $roleAssignments = @()
        foreach ($user in $users | Where-Object { Get-NetIPObjectPropertyValue -InputObject $_ -Name 'id' }) {
            $roleAssignments += Ensure-NetIPGlobalAdministratorAssignment -User $user -RoleDefinition $roleDefinition -Apply $true
        }

        Write-NetIPLog -Message 'Phase 1a step 5/10: Håndterer administrator-SSPR...'
        $adminSSPRResult = if ($config.DisableAdminSSPR) {
            $result = Set-NetIPAdminSSPRDisabled -Apply $true
            Write-NetIPLog -Level WARN -Message 'Admin SSPR ændringen kan tage op til 60 minutter før den slår igennem.'
            $result
        }
        else {
            Write-NetIPLog -Message 'Administrator-SSPR ændres ikke.'
            [pscustomobject]@{
                Setting = 'allowedToUseSSPR'
                PreviousValue = $null
                DesiredValue = $null
                Status = 'Skipped'
                Detail = 'Administrator-SSPR change was not selected.'
            }
        }

        Write-NetIPLog -Message 'Phase 1a step 6/10: Opretter Temporary Access Pass for begge konti...'
        $temporaryAccessPasses = @()
        foreach ($user in $users | Where-Object { Get-NetIPObjectPropertyValue -InputObject $_ -Name 'id' }) {
            $temporaryAccessPasses += New-NetIPTemporaryAccessPass -User $user -LifetimeInMinutes 120 -IsUsableOnce $true -Apply $true
        }

        Write-NetIPLog -Message 'Phase 1a step 7/10: Sikrer gruppemedlemskab...'
        $membership = @()
        if ($config.AddUsersToGroup) {
            foreach ($user in $users | Where-Object { Get-NetIPObjectPropertyValue -InputObject $_ -Name 'id' }) {
                $membership += Ensure-NetIPGroupMember -Group $group -User $user -Apply $true
            }
        }
        else {
            $membership += [pscustomobject]@{ Status='Skipped'; Detail='Gruppemedlemskab er fravalgt.' }
        }

        Write-NetIPLog -Message 'Phase 1a step 8/10: Henter eksisterende Conditional Access policies...'
        $policies = @(Get-NetIPConditionalAccessPolicies)
        $backupPath = ''
        $caResults = @()
        $alreadyExcluded = @()
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
            Write-NetIPLog -Message 'Phase 1a step 9/10: Backupper og ekskluderer CA-BreakGlass-Exclude fra eksisterende CA policies...'
            $backupPath = Backup-NetIPConditionalAccessPolicies -Policies $policies -OutputFolder $output
            $caResults = Add-NetIPGroupExclusionToCAPolicies -Policies $policies -GroupId $groupId -Apply $true
        }
        else {
            Write-NetIPLog -Message 'Phase 1a step 9/10: Conditional Access patching er fravalgt.'
        }

        Write-NetIPLog -Message 'Phase 1a step 10/10: Gemmer Phase 1-resultat og genererer handoff...'
        $changed = @($caResults | Where-Object Status -eq 'Patched')
        $failed = @($caResults | Where-Object Status -eq 'Failed')
        $result = [pscustomobject]@{
            Phase = 'Phase 1a'
            TenantDisplayName = $tenant.TenantDisplayName
            TenantId = $tenant.TenantId
            Timestamp = (Get-Date).ToString('o')
            Operator = $sync.State.GraphAccount
            OnMicrosoftDomain = $tenant.OnMicrosoftDomain
            Account1 = [pscustomobject]@{
                DisplayName=$config.DisplayName1
                UserPrincipalName=$upn1
                Id=[string](Get-NetIPObjectPropertyValue -InputObject $users[0] -Name 'id')
                AccountEnabled=Get-NetIPObjectPropertyValue -InputObject $users[0] -Name 'accountEnabled'
                Status=[string](Get-NetIPObjectPropertyValue -InputObject $users[0] -Name 'EnsureStatus')
            }
            Account2 = [pscustomobject]@{
                DisplayName=$config.DisplayName2
                UserPrincipalName=$upn2
                Id=[string](Get-NetIPObjectPropertyValue -InputObject $users[1] -Name 'id')
                AccountEnabled=Get-NetIPObjectPropertyValue -InputObject $users[1] -Name 'accountEnabled'
                Status=[string](Get-NetIPObjectPropertyValue -InputObject $users[1] -Name 'EnsureStatus')
            }
            Group = [pscustomobject]@{ DisplayName=$groupDisplayName; Id=$groupId; Status=$groupStatus }
            GroupMembership = $membership
            RoleAssignments = $roleAssignments
            AdminSSPR = $adminSSPRResult
            TemporaryAccessPassSummary = @($temporaryAccessPasses | ForEach-Object {
                [pscustomobject]@{
                    UserPrincipalName = Get-NetIPObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName'
                    LifetimeInMinutes = Get-NetIPObjectPropertyValue -InputObject $_ -Name 'lifetimeInMinutes'
                    IsUsableOnce = Get-NetIPObjectPropertyValue -InputObject $_ -Name 'isUsableOnce'
                    Status = Get-NetIPObjectPropertyValue -InputObject $_ -Name 'Status'
                }
            })
            AuthenticationStrength = [pscustomobject]@{ id=''; displayName=$config.AuthenticationStrengthName; Status='PendingPhase2' }
            BreakGlassCAPolicy = [pscustomobject]@{ id=''; displayName=$config.BreakGlassCAPolicyName; state='PendingPhase2'; Status='PendingPhase2' }
            CAExclusionsEnabled = [bool]$config.PatchCAPolicies
            CAPoliciesChangedCount = $changed.Count
            CAPoliciesChanged = $changed
            CAPoliciesAlreadyExcluded = $alreadyExcluded
            CAPoliciesFailed = $failed
            CABackupPath = $backupPath
            Warnings = @(
                'Phase 1b: Log ind på begge break-glass konti med TAP og registrer to FIDO2 security keys pr. konto.'
                'Admin SSPR ændringer kan tage op til 60 minutter før de slår igennem.'
            )
        }
        $sync.State.Result = $result
        $sync.State.Phase1Result = $result
        Save-NetIPResultJson -Result $result -OutputFolder $output | Out-Null

        $handoffResult = $result | Select-Object *
        $handoffResult | Add-Member -MemberType NoteProperty -Name SensitiveTemporaryAccessPasses -Value $temporaryAccessPasses -Force
        $handoff = New-NetIPHandoffHtml -Result $handoffResult -OutputFolder $output
        $sync.State.HandoffPath = $handoff

        $secretsToShow = @($createdPasswords + $temporaryAccessPasses)
        if ($secretsToShow.Count -gt 0) {
            $sync.State.CreatedPasswords = $secretsToShow
            Write-NetIPLog -Message 'Viser initiale passwords/TAP i separat vindue. De bliver ikke skrevet til almindelig log.'
            Show-NetIPCreatedPasswordsOnce -CreatedPasswords $secretsToShow
        }
        $sync.Form.Dispatcher.Invoke([System.Action]{
            $sync.WPFOutputFolder.Text = $sync.State.OutputFolder
            $sync.WPFHandoffPath.Text = $sync.State.HandoffPath
            Invoke-NetIPWPFButton -Name 'WPFStepManualFido'
        })
        Write-NetIPStatus -Message 'Phase 1a er færdig. Fortsæt med manuel FIDO2-registrering.'
    }
}

function Invoke-NetIPApplyPhase2 {
    [CmdletBinding()]
    param()

    if (-not $sync.State.Plan) {
        [System.Windows.MessageBox]::Show('Generér en plan før Phase 2.', $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }
    $config = Get-NetIPConfigFromUI
    $answer = [System.Windows.MessageBox]::Show('Skal eksisterende Temporary Access Pass-koder på de to break-glass konti slettes som en del af Phase 2?', $sync.App.Name, 'YesNoCancel', 'Question')
    if ($answer -eq 'Cancel') { return }
    $deleteTap = ($answer -eq 'Yes')

    Invoke-NetIPRunspace -ArgumentList @($config, $deleteTap) -ScriptBlock {
        param($config, $deleteTap)
        Write-NetIPStatus -Busy -Message 'Phase 2: refresher FIDO2 og opretter disabled CA-policy...'
        $tenant = Get-NetIPTenantInfo
        $output = if ($sync.State.OutputFolder) { $sync.State.OutputFolder } else { New-NetIPOutputFolder -TenantId $tenant.TenantId }
        $sync.State.OutputFolder = $output
        New-Item -ItemType Directory -Force -Path $output | Out-Null

        $upn1 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix1 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        $upn2 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix2 -OnMicrosoftDomain $tenant.OnMicrosoftDomain

        Write-NetIPLog -Message 'Phase 2 step 1/6: Refresher de to break-glass konti...'
        $users = @(
            Get-NetIPUserByUpn -UserPrincipalName $upn1
            Get-NetIPUserByUpn -UserPrincipalName $upn2
        ) | Where-Object { $_ }
        if ($users.Count -ne 2) { throw 'Phase 2 kræver at begge break-glass konti findes i tenant.' }

        Write-NetIPLog -Message 'Phase 2 step 2/6: Henter FIDO2 methods og AAGUIDs fra begge konti...'
        $fidoMethods = @()
        foreach ($user in $users) {
            $upn = [string](Get-NetIPObjectPropertyValue -InputObject $user -Name 'userPrincipalName')
            $methods = @(Get-NetIPFido2MethodsForUser -UserPrincipalName $upn)
            foreach ($method in $methods) {
                $method | Add-Member -MemberType NoteProperty -Name UserPrincipalName -Value $upn -Force
                $fidoMethods += $method
            }
        }
        $extractedAAGUIDs = @($fidoMethods | ForEach-Object {
            [string](Get-NetIPObjectPropertyValue -InputObject $_ -Name 'aaGuid')
        } | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
        $mergedAAGUIDs = @(@($config.AAGUIDs) + $extractedAAGUIDs | Where-Object { $_ } | Select-Object -Unique)
        if ($mergedAAGUIDs.Count -lt 1) { throw 'Der blev ikke fundet nogen FIDO2 AAGUIDs på de to break-glass konti. Registrer FIDO2 keys først.' }
        foreach ($guid in $mergedAAGUIDs) { Write-NetIPLog -Level PASS -Message "AAGUID klar til authentication strength: $guid" }

        Write-NetIPLog -Message 'Phase 2 step 3/6: Håndterer TAP cleanup...'
        $tapCleanup = if ($deleteTap) {
            Remove-NetIPTemporaryAccessPassMethods -Users $users -Apply $true
        }
        else {
            Write-NetIPLog -Message 'TAP cleanup blev fravalgt.'
            @([pscustomobject]@{ Status='Skipped'; Detail='Brugeren valgte ikke at slette TAP.' })
        }

        Write-NetIPLog -Message 'Phase 2 step 4/6: Opretter/opdaterer BreakGlass-FIDO2 authentication strength...'
        $authenticationStrengthResult = Ensure-NetIPAuthenticationStrength -DisplayName $config.AuthenticationStrengthName -Description $config.AuthenticationStrengthDescription -AllowedAAGUIDs $mergedAAGUIDs -Apply $true
        $strengthId = [string](Get-NetIPObjectPropertyValue -InputObject $authenticationStrengthResult -Name 'id')

        Write-NetIPLog -Message 'Phase 2 step 5/6: Opretter dedikeret CA-policy som disabled og assigner de to konti direkte...'
        $userIds = @($users | ForEach-Object { [string](Get-NetIPObjectPropertyValue -InputObject $_ -Name 'id') })
        $breakGlassCAPolicyResult = Ensure-NetIPBreakGlassCAPolicy -DisplayName $config.BreakGlassCAPolicyName -UserIds $userIds -AuthenticationStrengthId $strengthId -Enabled $false -Apply $true

        Write-NetIPLog -Message 'Phase 2 step 6/6: Gemmer Phase 2-resultat og opdaterer handoff...'
        $base = if ($sync.State.Phase1Result) { $sync.State.Phase1Result } elseif ($sync.State.Result) { $sync.State.Result } else { [pscustomobject]@{} }
        $result = $base | Select-Object *
        $result | Add-Member -MemberType NoteProperty -Name Phase -Value 'Phase 2' -Force
        $result | Add-Member -MemberType NoteProperty -Name Timestamp -Value (Get-Date).ToString('o') -Force
        $result | Add-Member -MemberType NoteProperty -Name Account1 -Value ([pscustomobject]@{
            DisplayName=$config.DisplayName1
            UserPrincipalName=$upn1
            Id=[string](Get-NetIPObjectPropertyValue -InputObject $users[0] -Name 'id')
            AccountEnabled=Get-NetIPObjectPropertyValue -InputObject $users[0] -Name 'accountEnabled'
            Status='Refreshed'
        }) -Force
        $result | Add-Member -MemberType NoteProperty -Name Account2 -Value ([pscustomobject]@{
            DisplayName=$config.DisplayName2
            UserPrincipalName=$upn2
            Id=[string](Get-NetIPObjectPropertyValue -InputObject $users[1] -Name 'id')
            AccountEnabled=Get-NetIPObjectPropertyValue -InputObject $users[1] -Name 'accountEnabled'
            Status='Refreshed'
        }) -Force
        $result | Add-Member -MemberType NoteProperty -Name Fido2Methods -Value $fidoMethods -Force
        $result | Add-Member -MemberType NoteProperty -Name ExtractedAAGUIDs -Value $mergedAAGUIDs -Force
        $result | Add-Member -MemberType NoteProperty -Name TAPCleanup -Value $tapCleanup -Force
        $result | Add-Member -MemberType NoteProperty -Name AuthenticationStrength -Value $authenticationStrengthResult -Force
        $result | Add-Member -MemberType NoteProperty -Name BreakGlassCAPolicy -Value $breakGlassCAPolicyResult -Force
        $sync.State.Result = $result
        Save-NetIPResultJson -Result $result -OutputFolder $output | Out-Null
        $handoff = New-NetIPHandoffHtml -Result $result -OutputFolder $output
        $sync.State.HandoffPath = $handoff

        $sync.Form.Dispatcher.Invoke([System.Action]{
            $sync.WPFAAGUIDs.Text = ($mergedAAGUIDs -join [Environment]::NewLine)
            $sync.WPFOutputFolder.Text = $sync.State.OutputFolder
            $sync.WPFHandoffPath.Text = $sync.State.HandoffPath
            Invoke-NetIPWPFButton -Name 'WPFStepHandoff'
        })
        Write-NetIPStatus -Message 'Phase 2 er færdig. CA-politikken er oprettet som disabled.'
    }
}
