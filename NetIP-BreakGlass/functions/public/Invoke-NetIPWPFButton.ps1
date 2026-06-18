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
        'WPFConnectTenant' { Invoke-NetIPConnectTenant }
        'WPFRunDiscovery' { Invoke-NetIPDiscovery }
        'WPFBuildPlan' { Invoke-NetIPBuildPlan }
        'WPFApplyConfiguration' { Invoke-NetIPApplyConfiguration }
        'WPFCycleNeutralNames' { Set-NetIPNeutralAccountNamePair }
        'WPFOpenOutputFolder' { Invoke-NetIPOpenOutputFolder }
        'WPFOpenHandoff' { Invoke-NetIPOpenHandoff }
        default { Write-NetIPLog -Level WARN -Message "Ukendt UI handling: $Name" }
    }
}

function Set-NetIPWPFStep {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Step)

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
