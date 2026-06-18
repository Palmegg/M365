function Invoke-NetIPWPFButton {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    switch ($Name) {
        'WPFStepWelcome' { Set-NetIPWPFStep -Step 'Welcome' }
        'WPFStepConnect' { Set-NetIPWPFStep -Step 'Connect' }
        'WPFStepDiscovery' { Set-NetIPWPFStep -Step 'Discovery' }
        'WPFStepConfig' { Set-NetIPWPFStep -Step 'Config' }
        'WPFStepPlan' { Set-NetIPWPFStep -Step 'Plan' }
        'WPFStepApply' { Set-NetIPWPFStep -Step 'Apply' }
        'WPFStepHandoff' { Set-NetIPWPFStep -Step 'Handoff' }
        'WPFBackStep' { Move-NetIPWPFStep -Direction -1 }
        'WPFNextStep' { Move-NetIPWPFStep -Direction 1 }
        'WPFConnectTenant' { Invoke-NetIPConnectTenant }
        'WPFRunDiscovery' { Invoke-NetIPDiscovery }
        'WPFBuildPlan' { Invoke-NetIPBuildPlan }
        'WPFApplyConfiguration' { Invoke-NetIPApplyConfiguration }
        'WPFCycleNeutralNames' { Set-NetIPNeutralAccountNamePair }
        'WPFFetchAAGUIDs' { Invoke-NetIPFetchAAGUIDs }
        'WPFOpenOutputFolder' { Invoke-NetIPOpenOutputFolder }
        'WPFOpenHandoff' { Invoke-NetIPOpenHandoff }
        default { Write-NetIPLog -Level WARN -Message "Ukendt UI handling: $Name" }
    }
}

function Set-NetIPWPFStep {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Step)

    $sync.UI.CurrentStep = $Step
    if ($Step -eq 'Config') {
        $sync.UI.ConfigVisited = $true
    }

    foreach ($page in @('WPFPageWelcome','WPFPageConnect','WPFPageDiscovery','WPFPageConfig','WPFPagePlan','WPFPageApply','WPFPageHandoff')) {
        $sync[$page].Visibility = 'Collapsed'
    }
    $target = switch ($Step) {
        'Welcome' { 'WPFPageWelcome' }
        'Connect' { 'WPFPageConnect' }
        'Discovery' { 'WPFPageDiscovery' }
        'Config' { 'WPFPageConfig' }
        'Plan' { 'WPFPagePlan' }
        'Apply' { 'WPFPageApply' }
        'Handoff' { 'WPFPageHandoff' }
    }
    $sync[$target].Visibility = 'Visible'
    Update-NetIPUIState
}

function Move-NetIPWPFStep {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet(-1,1)][int] $Direction)

    $steps = @('Welcome','Connect','Discovery','Config','Plan','Apply','Handoff')
    $current = [string]$sync.UI.CurrentStep
    $index = [array]::IndexOf($steps, $current)
    if ($index -lt 0) { $index = 0 }

    $targetIndex = $index + $Direction
    if ($targetIndex -lt 0 -or $targetIndex -ge $steps.Count) { return }

    $targetStep = $steps[$targetIndex]
    $targetButtonName = @{
        Welcome = 'WPFStepWelcome'
        Connect = 'WPFStepConnect'
        Discovery = 'WPFStepDiscovery'
        Config = 'WPFStepConfig'
        Plan = 'WPFStepPlan'
        Apply = 'WPFStepApply'
        Handoff = 'WPFStepHandoff'
    }[$targetStep]

    if ($Direction -gt 0 -and $sync[$targetButtonName] -and -not [bool]$sync[$targetButtonName].IsEnabled) {
        [System.Windows.MessageBox]::Show('Dette trin er ikke klar endnu. Udfør først handlingen på den nuværende side.', $sync.App.Name, 'OK', 'Information') | Out-Null
        return
    }

    Set-NetIPWPFStep -Step $targetStep
}
