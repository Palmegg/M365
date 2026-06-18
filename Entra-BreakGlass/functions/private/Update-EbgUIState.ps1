function Update-EbgUIState {
    [CmdletBinding()]
    param()

    if (-not $sync.Form) { return }
    if (-not $sync.Form.Dispatcher.CheckAccess()) {
        [void]$sync.Form.Dispatcher.Invoke([System.Action]{ Update-EbgUIState | Out-Null })
        return
    }

    $domain = [string]$sync.State.OnMicrosoftDomain
    if ($sync.WPFDomain) { $sync.WPFDomain.Text = $domain }
    if ($sync.WPFUpnPreview1 -and $domain) { $sync.WPFUpnPreview1.Text = "$(if($sync.WPFUserPrefix1){$sync.WPFUserPrefix1.Text})@$domain" }
    if ($sync.WPFUpnPreview2 -and $domain) { $sync.WPFUpnPreview2.Text = "$(if($sync.WPFUserPrefix2){$sync.WPFUserPrefix2.Text})@$domain" }
    if ($sync.WPFPhase2Domain) { $sync.WPFPhase2Domain.Text = $domain }
    if ($sync.WPFPhase2UpnPreview -and $domain) {
        $prefix1 = if ($sync.WPFPhase2UserPrefix1 -and -not [string]::IsNullOrWhiteSpace($sync.WPFPhase2UserPrefix1.Text)) { $sync.WPFPhase2UserPrefix1.Text.Trim() } elseif ($sync.WPFUserPrefix1) { $sync.WPFUserPrefix1.Text.Trim() } else { '' }
        $prefix2 = if ($sync.WPFPhase2UserPrefix2 -and -not [string]::IsNullOrWhiteSpace($sync.WPFPhase2UserPrefix2.Text)) { $sync.WPFPhase2UserPrefix2.Text.Trim() } elseif ($sync.WPFUserPrefix2) { $sync.WPFUserPrefix2.Text.Trim() } else { '' }
        $sync.WPFPhase2UpnPreview.Text = "$prefix1@$domain$([Environment]::NewLine)$prefix2@$domain"
    }
    Update-EbgAAGUIDSourceOptions
    if ($sync.WPFGraphStatus) {
        $sync.WPFGraphStatus.Text = if ($sync.State.GraphConnected) {
            if ($sync.State.Language -eq 'en-US') { 'Yes' } else { 'Ja' }
        }
        else {
            if ($sync.State.Language -eq 'en-US') { 'No' } else { 'Nej' }
        }
    }
    if ($sync.WPFGraphAccount) { $sync.WPFGraphAccount.Text = [string]$sync.State.GraphAccount }
    if ($sync.WPFTenantId) { $sync.WPFTenantId.Text = [string]$sync.State.TenantId }
    if ($sync.WPFTenantName) { $sync.WPFTenantName.Text = [string]$sync.State.TenantDisplayName }
    if ($sync.WPFOnMicrosoftDomain) { $sync.WPFOnMicrosoftDomain.Text = [string]$sync.State.OnMicrosoftDomain }
    if ($sync.WPFOutputFolder) { $sync.WPFOutputFolder.Text = [string]$sync.State.OutputFolder }
    if ($sync.WPFHandoffPath) { $sync.WPFHandoffPath.Text = [string]$sync.State.HandoffPath }
    $risk = [bool]$sync.WPFWelcomeRiskAccepted.IsChecked
    $hasGraph = [bool]$sync.State.GraphConnected
    $hasDiscovery = $null -ne $sync.State.Discovery
    $hasVisitedConfig = [bool]$sync.UI.ConfigVisited
    $hasPlan = $null -ne $sync.State.Plan
    $hasPhase1 = $null -ne $sync.State.Phase1Result
    $hasHandoff = -not [string]::IsNullOrWhiteSpace([string]$sync.State.HandoffPath)
    $resumePhase2 = [string]$sync.State.StartMode -eq 'Phase2'
    $regularSSPROnly = [bool]$sync.WPFRegularSSPROnly.IsChecked
    $canPhase2 = if ($resumePhase2) {
        $risk -and $hasGraph
    }
    else {
        $risk -and $hasGraph -and $hasPhase1
    }

    $sync.WPFStepWelcome.IsEnabled = $true
    $sync.WPFStepConnect.IsEnabled = $risk
    $sync.WPFStepDiscovery.IsEnabled = (-not $resumePhase2) -and $risk -and $hasGraph
    $sync.WPFStepConfig.IsEnabled = (-not $resumePhase2) -and $risk -and $hasGraph -and $hasDiscovery
    $sync.WPFStepPlan.IsEnabled = (-not $resumePhase2) -and $risk -and $hasGraph -and $hasDiscovery -and $hasVisitedConfig
    $sync.WPFStepApply.IsEnabled = (-not $resumePhase2) -and $risk -and $hasGraph -and $hasPlan
    $sync.WPFStepManualFido.IsEnabled = (-not $resumePhase2) -and $risk -and $hasPhase1
    $sync.WPFStepPhase2.IsEnabled = $canPhase2
    $sync.WPFStepHandoff.IsEnabled = $risk -and $hasHandoff

    $stepMap = @{
        Welcome = 'WPFStepWelcome'
        Connect = 'WPFStepConnect'
        Discovery = 'WPFStepDiscovery'
        Config = 'WPFStepConfig'
        Plan = 'WPFStepPlan'
        Apply = 'WPFStepApply'
        ManualFido = 'WPFStepManualFido'
        Phase2 = 'WPFStepPhase2'
        Handoff = 'WPFStepHandoff'
    }
    $activeBrush = $sync.Form.Resources['AccentSoft']
    $inactiveBrush = $sync.Form.Resources['PanelRaised']
    $activeBorderBrush = $sync.Form.Resources['Accent']
    $inactiveBorderBrush = $sync.Form.Resources['BorderSoft']
    foreach ($entry in $stepMap.GetEnumerator()) {
        $button = $sync[$entry.Value]
        if (-not $button) { continue }
        if ([string]$sync.UI.CurrentStep -eq [string]$entry.Key) {
            $button.Background = $activeBrush
            $button.BorderBrush = $activeBorderBrush
        }
        else {
            $button.Background = $inactiveBrush
            $button.BorderBrush = $inactiveBorderBrush
        }
    }

    $steps = @(Get-EbgWorkflowSteps)
    $titles = @{
        Welcome = 'Start'
        Connect = 'Forbind'
        Discovery = 'Discovery'
        Config = 'Phase 1 konfiguration'
        Plan = 'Phase 1 plan'
        Apply = 'Phase 1a'
        ManualFido = 'Phase 1b manuel FIDO2'
        Phase2 = 'Phase 2'
        Handoff = 'Handoff'
    }
    $current = [string]$sync.UI.CurrentStep
    $index = [array]::IndexOf($steps, $current)
    if ($index -lt 0) { $index = 0; $current = 'Welcome' }

    if ($sync.WPFCurrentStepText) {
        $sync.WPFCurrentStepText.Text = "Step $($index + 1) af $($steps.Count): $($titles[$current])"
    }
    if ($sync.WPFCurrentPhaseText) {
        $phaseLabel = switch ($current) {
            { $_ -in @('Welcome','Connect','Discovery','Config','Plan') } { if ($resumePhase2) { 'Forberedelse til Phase 2' } else { 'Forberedelse' } }
            'Apply' { 'Phase 1a - automatiske tenant-ændringer' }
            'ManualFido' { 'Phase 1b - manuel FIDO2 registrering' }
            'Phase2' { 'Phase 2 - FIDO2 enforcement forberedes' }
            'Handoff' { 'Handoff' }
            default { 'Forberedelse' }
        }
        $sync.WPFCurrentPhaseText.Text = "Aktuel fase: $phaseLabel"
    }

    if ($sync.WPFCreateRegularSSPRScopeGroup -and $regularSSPROnly) {
        $sync.WPFCreateRegularSSPRScopeGroup.IsChecked = $true
    }
    if ($sync.WPFRegularSSPRRulePreview -and $sync.WPFRegularSSPRAdmin1 -and $sync.WPFRegularSSPRAdmin2) {
        $selectedId1 = if ($sync.WPFRegularSSPRAdmin1.SelectedItem) { [string](Get-EbgObjectPropertyValue -InputObject $sync.WPFRegularSSPRAdmin1.SelectedItem -Name 'id') } else { '' }
        $selectedId2 = if ($sync.WPFRegularSSPRAdmin2.SelectedItem) { [string](Get-EbgObjectPropertyValue -InputObject $sync.WPFRegularSSPRAdmin2.SelectedItem -Name 'id') } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($selectedId1) -and -not [string]::IsNullOrWhiteSpace($selectedId2) -and $selectedId1 -ne $selectedId2) {
            $sync.WPFRegularSSPRRulePreview.Text = New-EbgRegularSSPRMembershipRule -Account1ObjectId $selectedId1 -Account2ObjectId $selectedId2
        }
        elseif ([string]::IsNullOrWhiteSpace($sync.WPFRegularSSPRRulePreview.Text) -or $sync.WPFRegularSSPRRulePreview.Text -match '<Account') {
            $sync.WPFRegularSSPRRulePreview.Text = '(user.accountEnabled -eq true) -and (user.userType -eq "Member") -and (user.objectId -notIn ["<Account 1 objectId>","<Account 2 objectId>"])'
        }
    }
    foreach ($phase1Option in @('WPFCreateUsers','WPFCreateGroup','WPFAddUsersToGroup','WPFDisableAdminSSPR','WPFPatchCAPolicies')) {
        if ($sync[$phase1Option]) { $sync[$phase1Option].IsEnabled = -not $regularSSPROnly }
    }
    if ($sync.WPFCreateRegularSSPRScopeGroup) {
        $sync.WPFCreateRegularSSPRScopeGroup.IsEnabled = -not $regularSSPROnly
    }
    if ($sync.WPFApplyIntro) {
        $sync.WPFApplyIntro.Text = if ($regularSSPROnly) {
            'Dette trin opretter/opdaterer kun regular SSPR dynamic security group for eksisterende break-glass konti. Der oprettes ikke brugere, TAP, roller, CA exclusions, FIDO2 policy eller Admin SSPR ændringer.'
        }
        else {
            'Dette trin opretter/genbruger CA-BreakGlass-Exclude, de to konti, regular SSPR scope-gruppe, Global Administrator assignments, Admin SSPR, TAP, gruppemedlemskab, FIDO2/passkey method policy, registration campaign exclusion og CA exclusions.'
        }
    }
    if ($sync.WPFApplyWarning) {
        $sync.WPFApplyWarning.Text = if ($regularSSPROnly) {
            'Begge break-glass konti skal allerede findes. Gruppen skal stadig vælges manuelt under Entra Password reset > Properties > Selected.'
        }
        else {
            'Admin SSPR kan tage op til 60 minutter før ændringen slår igennem. TAP oprettes som genanvendelig i 2 timer.'
        }
    }
    if ($sync.WPFApplyConfiguration -and -not [bool]$sync.UI.ProcessRunning) {
        $sync.WPFApplyConfiguration.Content = if ($regularSSPROnly) { 'Kør regular SSPR-only' } else { 'Kør Phase 1a' }
    }

    $phaseDefinitions = @(
        @{
            Key='Prep'; Card='WPFPhasePrepCard'; Title='WPFPhasePrepTitle'; Status='WPFPhasePrepStatus'
            IsActive=($current -in @('Welcome','Connect','Discovery','Config','Plan'))
            IsDone=($current -in @('Apply','ManualFido','Phase2','Handoff'))
            IsAvailable=$true
            ActiveText=$(if ($resumePhase2) { 'Aktiv: start og connect' } else { 'Aktiv: start, connect, discovery og plan' })
            DoneText='Færdig'
            LockedText=''
            ReadyText='Klar'
        },
        @{
            Key='Phase1'; Card='WPFPhase1Card'; Title='WPFPhase1Title'; Status='WPFPhase1Status'
            IsActive=($current -eq 'Apply')
            IsDone=($hasPhase1 -or $resumePhase2)
            IsAvailable=($hasPlan -or $resumePhase2)
            ActiveText=$(if ($regularSSPROnly) { 'Aktiv: regular SSPR group only' } else { 'Aktiv: opretter konti, TAP og CA exclusions' })
            DoneText=$(if ($resumePhase2) { 'Springes over - Phase 1 er allerede udført' } else { 'Færdig' })
            LockedText='Låst indtil plan er genereret'
            ReadyText='Klar til kørsel'
        },
        @{
            Key='Manual'; Card='WPFPhaseManualCard'; Title='WPFPhaseManualTitle'; Status='WPFPhaseManualStatus'
            IsActive=($current -eq 'ManualFido')
            IsDone=($current -in @('Phase2','Handoff') -or ($resumePhase2 -and $current -notin @('Welcome','Connect','Discovery','Config')))
            IsAvailable=($hasPhase1 -or $resumePhase2)
            ActiveText='Aktiv: registrer 2 FIDO2 keys pr. konto'
            DoneText=$(if ($resumePhase2) { 'Bekræftet før resume' } else { 'Færdig eller bekræftet' })
            LockedText='Låst indtil Phase 1a er færdig'
            ReadyText='Klar efter Phase 1a'
        },
        @{
            Key='Phase2'; Card='WPFPhase2Card'; Title='WPFPhase2Title'; Status='WPFPhase2Status'
            IsActive=($current -eq 'Phase2')
            IsDone=($current -eq 'Handoff' -and $hasHandoff)
            IsAvailable=$canPhase2
            ActiveText='Aktiv: AAGUID, auth strength og disabled CA policy'
            DoneText='Færdig'
            LockedText='Låst indtil FIDO2 er registreret manuelt'
            ReadyText='Klar efter manuel FIDO2'
        },
        @{
            Key='Handoff'; Card='WPFPhaseHandoffCard'; Title='WPFPhaseHandoffTitle'; Status='WPFPhaseHandoffStatus'
            IsActive=($current -eq 'Handoff')
            IsDone=$false
            IsAvailable=$hasHandoff
            ActiveText='Aktiv: rapport og næste steps'
            DoneText='Færdig'
            LockedText='Låst indtil rapport er genereret'
            ReadyText='Klar'
        }
    )
    $doneBrush = $sync.Form.Resources['AccentSoft']
    $activePhaseBrush = $sync.Form.Resources['ButtonHoverBackground']
    $lockedBrush = $sync.Form.Resources['ButtonDisabledBackground']
    $readyBrush = $sync.Form.Resources['PanelRaised']
    $doneBorderBrush = $sync.Form.Resources['Accent']
    $activePhaseBorderBrush = $sync.Form.Resources['Accent']
    $lockedBorderBrush = $sync.Form.Resources['BorderSoft']
    $readyBorderBrush = $sync.Form.Resources['BorderSoft']
    $primaryTextBrush = $sync.Form.Resources['TextPrimary']
    $mutedTextBrush = $sync.Form.Resources['TextMuted']
    $secondaryTextBrush = $sync.Form.Resources['TextSecondary']

    foreach ($phase in $phaseDefinitions) {
        $card = $sync[$phase.Card]
        $title = $sync[$phase.Title]
        $status = $sync[$phase.Status]
        if (-not $card) { continue }
        if ([bool]$phase.IsActive) {
            $card.Background = $activePhaseBrush
            $card.BorderBrush = $activePhaseBorderBrush
            if ($title) { $title.Foreground = $primaryTextBrush }
            if ($status) { $status.Foreground = $secondaryTextBrush; $status.Text = [string]$phase.ActiveText }
        }
        elseif ([bool]$phase.IsDone) {
            $card.Background = $doneBrush
            $card.BorderBrush = $doneBorderBrush
            if ($title) { $title.Foreground = $primaryTextBrush }
            if ($status) { $status.Foreground = $secondaryTextBrush; $status.Text = [string]$phase.DoneText }
        }
        elseif (-not [bool]$phase.IsAvailable) {
            $card.Background = $lockedBrush
            $card.BorderBrush = $lockedBorderBrush
            if ($title) { $title.Foreground = $mutedTextBrush }
            if ($status) { $status.Foreground = $mutedTextBrush; $status.Text = [string]$phase.LockedText }
        }
        else {
            $card.Background = $readyBrush
            $card.BorderBrush = $readyBorderBrush
            if ($title) { $title.Foreground = $primaryTextBrush }
            if ($status) { $status.Foreground = $mutedTextBrush; $status.Text = [string]$phase.ReadyText }
        }
    }

    if ($sync.WPFBackStep) {
        $sync.WPFBackStep.Visibility = if ($index -eq 0) { 'Hidden' } else { 'Visible' }
        $sync.WPFBackStep.Content = if ($index -gt 0) { "Tilbage til $($titles[$steps[$index - 1]])" } else { 'Tilbage' }
    }

    if ($sync.WPFNextStep) {
        if ($index -ge ($steps.Count - 1)) {
            $sync.WPFNextStep.Visibility = 'Hidden'
            $sync.WPFNextStep.IsEnabled = $false
            $sync.WPFNextStep.Content = 'Videre'
        }
        else {
            $nextStep = $steps[$index + 1]
            $nextButtonName = $stepMap[$nextStep]
            $sync.WPFNextStep.Visibility = 'Visible'
            $sync.WPFNextStep.IsEnabled = if ($sync[$nextButtonName]) { [bool]$sync[$nextButtonName].IsEnabled } else { $false }
            $sync.WPFNextStep.Content = "Videre til $($titles[$nextStep])"
        }
    }

    if ($sync.WPFStopDiscovery) {
        $sync.WPFStopDiscovery.IsEnabled = $false
    }
    if ($sync.WPFRunDiscovery) {
        $sync.WPFRunDiscovery.IsEnabled = -not [bool]$sync.UI.ProcessRunning
    }
    if ($sync.WPFRefreshRegularSSPRAdmins) {
        $sync.WPFRefreshRegularSSPRAdmins.IsEnabled = (-not [bool]$sync.UI.ProcessRunning) -and ($hasGraph -or [bool]$sync.App.Mock)
    }
    if ($sync.WPFBuildPlan) {
        $sync.WPFBuildPlan.IsEnabled = (-not [bool]$sync.UI.ProcessRunning) -and (-not $resumePhase2) -and $hasDiscovery -and $hasVisitedConfig
    }
    if ($sync.WPFApplyConfiguration) {
        $sync.WPFApplyConfiguration.IsEnabled = (-not [bool]$sync.UI.ProcessRunning) -and (-not $resumePhase2) -and $hasPlan -and (-not $hasPhase1)
    }
    if ($sync.WPFApplyPhase2) {
        $sync.WPFApplyPhase2.IsEnabled = (-not [bool]$sync.UI.ProcessRunning) -and $canPhase2
    }
    if ($sync.WPFFetchAAGUIDs) {
        $sync.WPFFetchAAGUIDs.IsEnabled = (-not [bool]$sync.UI.ProcessRunning) -and $hasGraph
    }
    if ($sync.WPFPhase2ActionHint) {
        $hasAAGUIDs = $false
        if ($sync.WPFAAGUIDs) {
            $hasAAGUIDs = @(ConvertFrom-EbgAAGUIDText -Text $sync.WPFAAGUIDs.Text).Count -gt 0
        }
        $sync.WPFPhase2ActionHint.Text = if ($hasAAGUIDs) {
            "AAGUID er klar. Tryk 'Kør Phase 2'. Først derefter kan du gå videre til Handoff."
        }
        else {
            "Hent AAGUID fra en konto med registreret FIDO2/passkey, og tryk derefter 'Kør Phase 2'."
        }
        $sync.WPFPhase2ActionHint.Foreground = if ($hasAAGUIDs) { [System.Windows.Media.Brushes]::LightGreen } else { $sync.Form.Resources['TextSecondary'] }
    }
}
