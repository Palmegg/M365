function Invoke-NetIPBuildPlan {
    [CmdletBinding()]
    param()

    if (-not $sync.State.GraphConnected -and -not $sync.App.Mock) {
        [System.Windows.MessageBox]::Show('Du skal først forbinde til Microsoft Graph.', $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }
    $config = Get-NetIPConfigFromUI
    Invoke-NetIPRunspace -ArgumentList @($config) -ScriptBlock {
        param($config)
        Write-NetIPStatus -Busy -Message 'Genererer plan...'
        $plan = New-NetIPPlanObject -Config $config -Discovery $sync.State.Discovery
        if (-not $sync.State.OutputFolder) {
            $sync.State.OutputFolder = New-NetIPOutputFolder -TenantId $plan.TenantId
        }
        $plan.OutputFolder = $sync.State.OutputFolder
        $plan.HandoffPath = Join-Path $sync.State.OutputFolder 'handoff.html'
        Export-NetIPJsonSafe -InputObject $plan -Path (Join-Path $sync.State.OutputFolder 'plan.json') -Depth 30 | Out-Null
        $text = @"
Tenant: $($plan.TenantDisplayName) / $($plan.TenantId)
Domain: $($plan.OnMicrosoftDomain)

Konto 1: $($plan.Account1DisplayName) / $($plan.Account1UPN) / $($plan.Account1Status)
Konto 2: $($plan.Account2DisplayName) / $($plan.Account2UPN) / $($plan.Account2Status)

Gruppe: $($plan.GroupName) / $($plan.GroupStatus)
Tilføj konti til gruppe: $($plan.AddAccountsToGroup)
Tildel Global Administrator: $($plan.AssignGlobalAdministrator) / scope $($plan.RoleAssignmentScope)
Administrator-SSPR enabled nu: $($plan.CurrentAdminSSPREnabled)
Administrator-SSPR plan: $($plan.PlannedAdminSSPRStatus)
Temporary Access Pass: $($plan.TemporaryAccessPassStatus)

Authentication strength: $($plan.AuthenticationStrengthName) / $($plan.AuthenticationStrengthStatus)
AAGUIDs: $(@($plan.AuthenticationStrengthAAGUIDs) -join ', ')
Dedikeret BG CA policy: $($plan.BreakGlassCAPolicyName) / $($plan.BreakGlassCAPolicyStatus)

Conditional Access policies fundet: $($plan.ConditionalAccessCount)
Patch CA policies: $($plan.PatchConditionalAccess)
Policies der ændres: $(@($plan.CAPoliciesToChange).Count)
Policies der allerede ekskluderer gruppen: $(@($plan.CAPoliciesAlreadyExcluded).Count)

Output folder: $($plan.OutputFolder)
Handoff: $($plan.HandoffPath)

Advarsler:
$($plan.Warnings -join [Environment]::NewLine)

JSON:
$($plan | ConvertTo-Json -Depth 30)
"@
        $sync.Form.Dispatcher.Invoke([System.Action]{
            $sync.WPFPlanText.Text = $text
            Invoke-NetIPWPFButton -Name 'WPFStepPlan'
        })
        Write-NetIPStatus -Message 'Plan er genereret.'
    }
}
