function Invoke-EbgWPFButton {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    switch ($Name) {
        'WPFStepWelcome' { Set-EbgWPFStep -Step 'Welcome' }
        'WPFStepConnect' { Set-EbgWPFStep -Step 'Connect' }
        'WPFStepDiscovery' { Set-EbgWPFStep -Step 'Discovery' }
        'WPFStepConfig' { Set-EbgWPFStep -Step 'Config' }
        'WPFStepPlan' { Set-EbgWPFStep -Step 'Plan' }
        'WPFStepApply' { Set-EbgWPFStep -Step 'Apply' }
        'WPFStepManualFido' { Set-EbgWPFStep -Step 'ManualFido' }
        'WPFStepPhase2' { Set-EbgWPFStep -Step 'Phase2' }
        'WPFStepHandoff' { Set-EbgWPFStep -Step 'Handoff' }
        'WPFBackStep' { Move-EbgWPFStep -Direction -1 }
        'WPFNextStep' { Move-EbgWPFStep -Direction 1 }
        'WPFConnectTenant' { Invoke-EbgConnectTenant }
        'WPFRunDiscovery' { Invoke-EbgDiscovery }
        'WPFStopDiscovery' { Stop-EbgCurrentTask }
        'WPFRefreshRegularSSPRAdmins' { Invoke-EbgLoadGlobalAdministrators }
        'WPFBuildPlan' { Invoke-EbgBuildPlan }
        'WPFApplyConfiguration' { Invoke-EbgApplyConfiguration }
        'WPFApplyPhase2' { Invoke-EbgApplyPhase2 }
        'WPFStopPhase2' { Stop-EbgCurrentTask }
        'WPFCycleNeutralNames' { Set-EbgNeutralAccountNamePair }
        'WPFRefreshAAGUIDAdmins' { Invoke-EbgLoadGlobalAdministrators }
        'WPFAddAAGUIDSourceAdmin' {
            $sync.State.AAGUIDSource2Visible = $true
            Update-EbgAAGUIDSourceOptions | Out-Null
            Update-EbgUIState | Out-Null
        }
        'WPFFetchAAGUIDs' { Invoke-EbgFetchAAGUIDs }
        'WPFOpenMfaSetup' { Invoke-EbgOpenUrl -Url 'https://aka.ms/mfasetup' }
        'WPFOpenPreProvisionMfaSetup' { Invoke-EbgOpenUrl -Url 'https://aka.ms/mfasetup' }
        'WPFOpenOutputFolder' { Invoke-EbgOpenOutputFolder }
        'WPFOpenHandoff' { Invoke-EbgOpenHandoff }
        default { Write-EbgLog -Level WARN -Message "Ukendt UI handling: $Name" }
    }
}

function Set-EbgWPFStep {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Step)

    $sync.UI.CurrentStep = $Step
    if ($Step -eq 'Config') {
        $sync.UI.ConfigVisited = $true
    }

    foreach ($page in @('WPFPageWelcome','WPFPageConnect','WPFPageDiscovery','WPFPageConfig','WPFPagePlan','WPFPageApply','WPFPageManualFido','WPFPagePhase2','WPFPageHandoff')) {
        $sync[$page].Visibility = 'Collapsed'
    }
    $target = switch ($Step) {
        'Welcome' { 'WPFPageWelcome' }
        'Connect' { 'WPFPageConnect' }
        'Discovery' { 'WPFPageDiscovery' }
        'Config' { 'WPFPageConfig' }
        'Plan' { 'WPFPagePlan' }
        'Apply' { 'WPFPageApply' }
        'ManualFido' { 'WPFPageManualFido' }
        'Phase2' { 'WPFPagePhase2' }
        'Handoff' { 'WPFPageHandoff' }
    }
    $sync[$target].Visibility = 'Visible'
    if ($sync.WPFPhase2LogPanel) {
        $sync.WPFPhase2LogPanel.Visibility = if ($Step -eq 'Phase2') { 'Visible' } else { 'Collapsed' }
    }
    Update-EbgUIState
}

function Move-EbgWPFStep {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int] $Direction)

    $steps = @(Get-EbgWorkflowSteps)
    $current = [string]$sync.UI.CurrentStep
    $index = [array]::IndexOf($steps, $current)
    if ($index -lt 0) { $index = 0 }

    $targetIndex = $index + $Direction
    if ($targetIndex -lt 0 -or $targetIndex -ge $steps.Count) { return }

    $targetStep = $steps[$targetIndex]
    $buttonMap = @{
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
    $targetButtonName = [string]$buttonMap[$targetStep]

    if ($Direction -gt 0 -and $sync[$targetButtonName] -and -not [bool]$sync[$targetButtonName].IsEnabled) {
        [System.Windows.MessageBox]::Show('Dette trin er ikke klar endnu. Udfør først handlingen på den nuværende side.', $sync.App.Name, 'OK', 'Information') | Out-Null
        return
    }

    Set-EbgWPFStep -Step $targetStep
}
