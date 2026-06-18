function Get-EbgWorkflowSteps {
    [CmdletBinding()]
    param()

    if ([string]$sync.State.StartMode -eq 'Phase2') {
        return @('Welcome','Connect','Phase2','Handoff')
    }

    return @('Welcome','Connect','Discovery','Config','Plan','Apply','ManualFido','Phase2','Handoff')
}
