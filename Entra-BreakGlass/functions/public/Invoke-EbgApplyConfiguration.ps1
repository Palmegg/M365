function Invoke-EbgApplyConfiguration {
    [CmdletBinding()]
    param()

    Invoke-EbgApplyPhase1
}

function Invoke-EbgApplyPhase1 {
    [CmdletBinding()]
    param()

    if (-not $sync.State.Plan) {
        [System.Windows.MessageBox]::Show('Generér en plan før du udfører Phase 1.', $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }
    if ($sync.UI.ProcessRunning) {
        [System.Windows.MessageBox]::Show('Der kører allerede en opgave. Vent til den er færdig.', $sync.App.Name, 'OK', 'Information') | Out-Null
        return
    }

    $config = Get-EbgConfigFromUI
    $plan = $sync.State.Plan
    $summary = @"
Phase 1a udfører:

1. Sikrer CA-BreakGlass-Exclude security group
2. Opretter/genbruger de 2 break-glass konti
3. Deaktiverer Admin SSPR tenant-wide: $($config.DisableAdminSSPR)
4. Opretter Temporary Access Pass: one-time use = Yes, duration = 2 hours
5. Tildeler direkte Global Administrator rolle
6. Melder konti ind i exclude-gruppen
7. Ekskluderer gruppen fra eksisterende CA policies: $($config.PatchCAPolicies)

Admin SSPR kan tage op til 60 minutter før ændringen slår igennem.
Initial passwords og TAP-koder skrives ikke til almindelig log.

Vil du fortsætte?
"@
    $answer = [System.Windows.MessageBox]::Show($summary, $sync.App.Name, 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }

    $sync.UI.ProcessRunning = $true
    if ($sync.WPFApplyConfiguration) { $sync.WPFApplyConfiguration.IsEnabled = $false }
    if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $true }
    Update-EbgUIState | Out-Null

    try {
        Write-EbgStatus -Busy -Message 'Phase 1a: anvender grundopsætning...'
        [System.Windows.Forms.Application]::DoEvents()

        Ensure-EbgGraphContext
        [System.Windows.Forms.Application]::DoEvents()

        Write-EbgLog -Message 'Phase 1a step 1/10: Henter tenant og klargør outputmappe...'
        Write-EbgStatus -Busy -Message 'Phase 1a step 1/10: henter tenant og klargør outputmappe...'
        [System.Windows.Forms.Application]::DoEvents()
        $tenant = Get-EbgTenantInfo
        $output = if ($sync.State.OutputFolder) { $sync.State.OutputFolder } else { New-EbgOutputFolder -TenantId $tenant.TenantId }
        $sync.State.OutputFolder = $output
        New-Item -ItemType Directory -Force -Path $output | Out-Null

        $upn1 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix1 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        $upn2 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix2 -OnMicrosoftDomain $tenant.OnMicrosoftDomain

        Write-EbgLog -Message 'Phase 1a step 2/10: Sikrer CA-BreakGlass-Exclude security group...'
        Write-EbgStatus -Busy -Message 'Phase 1a step 2/10: sikrer CA-BreakGlass-Exclude security group...'
        [System.Windows.Forms.Application]::DoEvents()
        $group = Ensure-EbgSecurityGroup -DisplayName $config.GroupName -Description $config.GroupDescription -CreateIfMissing ([bool]$config.CreateGroup) -Apply $true
        Write-EbgLog -Level PASS -Message "Gruppe håndteret: $($config.GroupName)"
        $groupId = [string](Get-EbgObjectPropertyValue -InputObject $group -Name 'id')
        $groupDisplayName = [string](Get-EbgObjectPropertyValue -InputObject $group -Name 'displayName')
        $groupStatus = [string](Get-EbgObjectPropertyValue -InputObject $group -Name 'EnsureStatus')

        Write-EbgLog -Message 'Phase 1a step 3/10: Sikrer de to break-glass konti...'
        Write-EbgStatus -Busy -Message 'Phase 1a step 3/10: sikrer de to break-glass konti...'
        [System.Windows.Forms.Application]::DoEvents()
        $createdPasswords = @()
        $users = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @(
            @{ DisplayName = $config.DisplayName1; Upn = $upn1 },
            @{ DisplayName = $config.DisplayName2; Upn = $upn2 }
        )) {
            $existing = Get-EbgUserByUpn -UserPrincipalName $item.Upn
            if ($existing) {
                $existing | Add-Member -MemberType NoteProperty -Name EnsureStatus -Value 'AlreadyExists' -Force
                $users.Add($existing)
                Write-EbgLog -Level PASS -Message "Bruger findes og genbruges: $($item.Upn)"
                continue
            }
            if (-not $config.CreateUsers) {
                $users.Add([pscustomobject]@{ id=''; displayName=$item.DisplayName; userPrincipalName=$item.Upn; EnsureStatus='SkippedMissing' })
                Write-EbgLog -Level WARN -Message "Bruger mangler og oprettes ikke: $($item.Upn)"
                continue
            }
            $password = New-EbgRandomPassword
            $user = New-BreakGlassUser -DisplayName $item.DisplayName -UserPrincipalName $item.Upn -Password $password
            $users.Add($user)
            $createdPasswords += [pscustomobject]@{ UserPrincipalName = $item.Upn; Password = $password }
            Write-EbgLog -Level PASS -Message "Bruger oprettet: $($item.Upn)"
        }

        $roleAssignments = @()

        Write-EbgLog -Message 'Phase 1a step 4/10: Håndterer administrator-SSPR...'
        Write-EbgStatus -Busy -Message 'Phase 1a step 4/10: håndterer administrator-SSPR...'
        [System.Windows.Forms.Application]::DoEvents()
        $adminSSPRResult = if ($config.DisableAdminSSPR) {
            $result = Set-EbgAdminSSPRDisabled -Apply $true
            Write-EbgLog -Level WARN -Message 'Admin SSPR ændringen kan tage op til 60 minutter før den slår igennem.'
            $result
        }
        else {
            Write-EbgLog -Message 'Administrator-SSPR ændres ikke.'
            [pscustomobject]@{
                Setting = 'allowedToUseSSPR'
                PreviousValue = $null
                DesiredValue = $null
                Status = 'Skipped'
                Detail = 'Administrator-SSPR change was not selected.'
            }
        }

        Write-EbgLog -Message 'Phase 1a step 5/10: Opretter Temporary Access Pass for begge konti før Global Administrator rollen tildeles...'
        Write-EbgStatus -Busy -Message 'Phase 1a step 5/10: opretter Temporary Access Pass for begge konti...'
        [System.Windows.Forms.Application]::DoEvents()
        $temporaryAccessPasses = @()
        foreach ($user in $users | Where-Object { Get-EbgObjectPropertyValue -InputObject $_ -Name 'id' }) {
            $temporaryAccessPasses += New-EbgTemporaryAccessPass -User $user -LifetimeInMinutes 120 -IsUsableOnce $true -Apply $true
        }

        Write-EbgLog -Message 'Phase 1a step 6/10: Tildeler direkte Global Administrator rolle...'
        Write-EbgStatus -Busy -Message 'Phase 1a step 6/10: tildeler direkte Global Administrator rolle...'
        [System.Windows.Forms.Application]::DoEvents()
        $roleDefinition = Get-EbgGlobalAdministratorRoleDefinition
        foreach ($user in $users | Where-Object { Get-EbgObjectPropertyValue -InputObject $_ -Name 'id' }) {
            $roleAssignments += Ensure-EbgGlobalAdministratorAssignment -User $user -RoleDefinition $roleDefinition -Apply $true
        }

        Write-EbgLog -Message 'Phase 1a step 7/10: Sikrer gruppemedlemskab...'
        Write-EbgStatus -Busy -Message 'Phase 1a step 7/10: sikrer gruppemedlemskab...'
        [System.Windows.Forms.Application]::DoEvents()
        $membership = @()
        if ($config.AddUsersToGroup) {
            foreach ($user in $users | Where-Object { Get-EbgObjectPropertyValue -InputObject $_ -Name 'id' }) {
                $membership += Ensure-EbgGroupMember -Group $group -User $user -Apply $true
            }
        }
        else {
            $membership += [pscustomobject]@{ Status='Skipped'; Detail='Gruppemedlemskab er fravalgt.' }
        }

        Write-EbgLog -Message 'Phase 1a step 8/10: Henter eksisterende Conditional Access policies...'
        Write-EbgStatus -Busy -Message 'Phase 1a step 8/10: henter eksisterende Conditional Access policies...'
        [System.Windows.Forms.Application]::DoEvents()
        $policies = @(Get-EbgConditionalAccessPolicies)
        $backupPath = ''
        $caResults = @()
        $alreadyExcluded = @()
        if ($group -and $groupId) {
            foreach ($policy in $policies) {
                $excludeGroups = @(Get-EbgObjectPropertyValue -InputObject (Get-EbgObjectPropertyValue -InputObject (Get-EbgObjectPropertyValue -InputObject $policy -Name 'conditions') -Name 'users') -Name 'excludeGroups')
                if ($excludeGroups -contains $groupId) {
                    $alreadyExcluded += [pscustomobject]@{
                        Policy = [string](Get-EbgObjectPropertyValue -InputObject $policy -Name 'displayName')
                        PolicyId = [string](Get-EbgObjectPropertyValue -InputObject $policy -Name 'id')
                        Status = 'AlreadyExcluded'
                    }
                }
            }
        }

        if ($config.PatchCAPolicies -and $group -and $groupId) {
            Write-EbgLog -Message 'Phase 1a step 9/10: Backupper og ekskluderer CA-BreakGlass-Exclude fra eksisterende CA policies...'
            Write-EbgStatus -Busy -Message 'Phase 1a step 9/10: backupper og ekskluderer gruppen fra CA policies...'
            [System.Windows.Forms.Application]::DoEvents()
            $backupPath = Backup-EbgConditionalAccessPolicies -Policies $policies -OutputFolder $output
            $caResults = Add-EbgGroupExclusionToCAPolicies -Policies $policies -GroupId $groupId -Apply $true
        }
        else {
            Write-EbgLog -Message 'Phase 1a step 9/10: Conditional Access patching er fravalgt.'
            Write-EbgStatus -Busy -Message 'Phase 1a step 9/10: Conditional Access patching er fravalgt.'
            [System.Windows.Forms.Application]::DoEvents()
        }

        Write-EbgLog -Message 'Phase 1a step 10/10: Gemmer Phase 1-resultat og genererer handoff...'
        Write-EbgStatus -Busy -Message 'Phase 1a step 10/10: gemmer resultat og genererer handoff...'
        [System.Windows.Forms.Application]::DoEvents()
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
                Id=[string](Get-EbgObjectPropertyValue -InputObject $users[0] -Name 'id')
                AccountEnabled=Get-EbgObjectPropertyValue -InputObject $users[0] -Name 'accountEnabled'
                Status=[string](Get-EbgObjectPropertyValue -InputObject $users[0] -Name 'EnsureStatus')
            }
            Account2 = [pscustomobject]@{
                DisplayName=$config.DisplayName2
                UserPrincipalName=$upn2
                Id=[string](Get-EbgObjectPropertyValue -InputObject $users[1] -Name 'id')
                AccountEnabled=Get-EbgObjectPropertyValue -InputObject $users[1] -Name 'accountEnabled'
                Status=[string](Get-EbgObjectPropertyValue -InputObject $users[1] -Name 'EnsureStatus')
            }
            Group = [pscustomobject]@{ DisplayName=$groupDisplayName; Id=$groupId; Status=$groupStatus }
            GroupMembership = $membership
            RoleAssignments = $roleAssignments
            AdminSSPR = $adminSSPRResult
            TemporaryAccessPassSummary = @($temporaryAccessPasses | ForEach-Object {
                [pscustomobject]@{
                    UserPrincipalName = Get-EbgObjectPropertyValue -InputObject $_ -Name 'UserPrincipalName'
                    LifetimeInMinutes = Get-EbgObjectPropertyValue -InputObject $_ -Name 'lifetimeInMinutes'
                    IsUsableOnce = Get-EbgObjectPropertyValue -InputObject $_ -Name 'isUsableOnce'
                    Status = Get-EbgObjectPropertyValue -InputObject $_ -Name 'Status'
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
        Save-EbgResultJson -Result $result -OutputFolder $output | Out-Null

        $handoffResult = $result | Select-Object *
        $handoffResult | Add-Member -MemberType NoteProperty -Name SensitiveTemporaryAccessPasses -Value $temporaryAccessPasses -Force
        $handoff = New-EbgHandoffHtml -Result $handoffResult -OutputFolder $output
        $sync.State.HandoffPath = $handoff

        $secretsToShow = @($createdPasswords + $temporaryAccessPasses)
        if ($secretsToShow.Count -gt 0) {
            $sync.State.CreatedPasswords = $secretsToShow
            Write-EbgLog -Message 'Viser initiale passwords/TAP i separat vindue. De bliver ikke skrevet til almindelig log.'
            Show-EbgCreatedPasswordsOnce -CreatedPasswords $secretsToShow
        }
        $sync.WPFOutputFolder.Text = $sync.State.OutputFolder
        $sync.WPFHandoffPath.Text = $sync.State.HandoffPath
        Invoke-EbgWPFButton -Name 'WPFStepManualFido'
        Write-EbgStatus -Message 'Phase 1a er færdig. Fortsæt med manuel FIDO2-registrering.'
    }
    catch {
        $message = ConvertTo-EbgRedactedError -ErrorRecord $_
        Write-EbgLog -Level ERROR -Message $message
        Write-EbgStatus -Message 'Phase 1a fejlede.'
        [System.Windows.MessageBox]::Show($message, $sync.App.Name, 'OK', 'Error') | Out-Null
    }
    finally {
        $sync.UI.ProcessRunning = $false
        if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $false }
        if ($sync.WPFApplyConfiguration) { $sync.WPFApplyConfiguration.IsEnabled = $true }
        Update-EbgUIState | Out-Null
    }
}

function Invoke-EbgApplyPhase2 {
    [CmdletBinding()]
    param()

    if (-not $sync.State.Plan) {
        [System.Windows.MessageBox]::Show('Generér en plan før Phase 2.', $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }
    $config = Get-EbgConfigFromUI
    $answer = [System.Windows.MessageBox]::Show('Skal eksisterende Temporary Access Pass-koder på de to break-glass konti slettes som en del af Phase 2?', $sync.App.Name, 'YesNoCancel', 'Question')
    if ($answer -eq 'Cancel') { return }
    $deleteTap = ($answer -eq 'Yes')

    Invoke-EbgRunspace -ArgumentList @($config, $deleteTap) -ScriptBlock {
        param($config, $deleteTap)
        Write-EbgStatus -Busy -Message 'Phase 2: refresher FIDO2 og opretter disabled CA-policy...'
        $tenant = Get-EbgTenantInfo
        $output = if ($sync.State.OutputFolder) { $sync.State.OutputFolder } else { New-EbgOutputFolder -TenantId $tenant.TenantId }
        $sync.State.OutputFolder = $output
        New-Item -ItemType Directory -Force -Path $output | Out-Null

        $upn1 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix1 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        $upn2 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix2 -OnMicrosoftDomain $tenant.OnMicrosoftDomain

        Write-EbgLog -Message 'Phase 2 step 1/6: Refresher de to break-glass konti...'
        $users = @(
            Get-EbgUserByUpn -UserPrincipalName $upn1
            Get-EbgUserByUpn -UserPrincipalName $upn2
        ) | Where-Object { $_ }
        if ($users.Count -ne 2) { throw 'Phase 2 kræver at begge break-glass konti findes i tenant.' }

        Write-EbgLog -Message 'Phase 2 step 2/6: Henter FIDO2 methods og AAGUIDs fra begge konti...'
        $fidoMethods = @()
        foreach ($user in $users) {
            $upn = [string](Get-EbgObjectPropertyValue -InputObject $user -Name 'userPrincipalName')
            $methods = @(Get-EbgFido2MethodsForUser -UserPrincipalName $upn)
            foreach ($method in $methods) {
                $method | Add-Member -MemberType NoteProperty -Name UserPrincipalName -Value $upn -Force
                $fidoMethods += $method
            }
        }
        $extractedAAGUIDs = @($fidoMethods | ForEach-Object {
            [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'aaGuid')
        } | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
        $mergedAAGUIDs = @(@($config.AAGUIDs) + $extractedAAGUIDs | Where-Object { $_ } | Select-Object -Unique)
        if ($mergedAAGUIDs.Count -lt 1) { throw 'Der blev ikke fundet nogen FIDO2 AAGUIDs på de to break-glass konti. Registrer FIDO2 keys først.' }
        foreach ($guid in $mergedAAGUIDs) { Write-EbgLog -Level PASS -Message "AAGUID klar til authentication strength: $guid" }

        Write-EbgLog -Message 'Phase 2 step 3/6: Håndterer TAP cleanup...'
        $tapCleanup = if ($deleteTap) {
            Remove-EbgTemporaryAccessPassMethods -Users $users -Apply $true
        }
        else {
            Write-EbgLog -Message 'TAP cleanup blev fravalgt.'
            @([pscustomobject]@{ Status='Skipped'; Detail='Brugeren valgte ikke at slette TAP.' })
        }

        Write-EbgLog -Message 'Phase 2 step 4/6: Opretter/opdaterer BreakGlass-FIDO2 authentication strength...'
        $authenticationStrengthResult = Ensure-EbgAuthenticationStrength -DisplayName $config.AuthenticationStrengthName -Description $config.AuthenticationStrengthDescription -AllowedAAGUIDs $mergedAAGUIDs -Apply $true
        $strengthId = [string](Get-EbgObjectPropertyValue -InputObject $authenticationStrengthResult -Name 'id')

        Write-EbgLog -Message 'Phase 2 step 5/6: Opretter dedikeret CA-policy som disabled og assigner de to konti direkte...'
        $userIds = @($users | ForEach-Object { [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id') })
        $breakGlassCAPolicyResult = Ensure-EbgBreakGlassCAPolicy -DisplayName $config.BreakGlassCAPolicyName -UserIds $userIds -AuthenticationStrengthId $strengthId -Enabled $false -Apply $true

        Write-EbgLog -Message 'Phase 2 step 6/6: Gemmer Phase 2-resultat og opdaterer handoff...'
        $base = if ($sync.State.Phase1Result) { $sync.State.Phase1Result } elseif ($sync.State.Result) { $sync.State.Result } else { [pscustomobject]@{} }
        $result = $base | Select-Object *
        $result | Add-Member -MemberType NoteProperty -Name Phase -Value 'Phase 2' -Force
        $result | Add-Member -MemberType NoteProperty -Name Timestamp -Value (Get-Date).ToString('o') -Force
        $result | Add-Member -MemberType NoteProperty -Name Account1 -Value ([pscustomobject]@{
            DisplayName=$config.DisplayName1
            UserPrincipalName=$upn1
            Id=[string](Get-EbgObjectPropertyValue -InputObject $users[0] -Name 'id')
            AccountEnabled=Get-EbgObjectPropertyValue -InputObject $users[0] -Name 'accountEnabled'
            Status='Refreshed'
        }) -Force
        $result | Add-Member -MemberType NoteProperty -Name Account2 -Value ([pscustomobject]@{
            DisplayName=$config.DisplayName2
            UserPrincipalName=$upn2
            Id=[string](Get-EbgObjectPropertyValue -InputObject $users[1] -Name 'id')
            AccountEnabled=Get-EbgObjectPropertyValue -InputObject $users[1] -Name 'accountEnabled'
            Status='Refreshed'
        }) -Force
        $result | Add-Member -MemberType NoteProperty -Name Fido2Methods -Value $fidoMethods -Force
        $result | Add-Member -MemberType NoteProperty -Name ExtractedAAGUIDs -Value $mergedAAGUIDs -Force
        $result | Add-Member -MemberType NoteProperty -Name TAPCleanup -Value $tapCleanup -Force
        $result | Add-Member -MemberType NoteProperty -Name AuthenticationStrength -Value $authenticationStrengthResult -Force
        $result | Add-Member -MemberType NoteProperty -Name BreakGlassCAPolicy -Value $breakGlassCAPolicyResult -Force
        $sync.State.Result = $result
        Save-EbgResultJson -Result $result -OutputFolder $output | Out-Null
        $handoff = New-EbgHandoffHtml -Result $result -OutputFolder $output
        $sync.State.HandoffPath = $handoff

        $sync.Form.Dispatcher.Invoke([System.Action]{
            $sync.WPFAAGUIDs.Text = ($mergedAAGUIDs -join [Environment]::NewLine)
            $sync.WPFOutputFolder.Text = $sync.State.OutputFolder
            $sync.WPFHandoffPath.Text = $sync.State.HandoffPath
            Invoke-EbgWPFButton -Name 'WPFStepHandoff'
        })
        Write-EbgStatus -Message 'Phase 2 er færdig. CA-politikken er oprettet som disabled.'
    }
}
