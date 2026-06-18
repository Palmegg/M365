function Invoke-EbgBuildPlan {
    [CmdletBinding()]
    param()

    if (-not $sync.State.GraphConnected -and -not $sync.App.Mock) {
        [System.Windows.MessageBox]::Show('Du skal først forbinde til Microsoft Graph.', $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }
    if ($sync.UI.ProcessRunning) {
        [System.Windows.MessageBox]::Show('Der kører allerede en opgave. Vent til den er færdig.', $sync.App.Name, 'OK', 'Information') | Out-Null
        return
    }

    $sync.UI.ProcessRunning = $true
    if ($sync.WPFBuildPlan) { $sync.WPFBuildPlan.IsEnabled = $false }
    if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $true }

    try {
        $config = Get-EbgConfigFromUI
        Write-EbgStatus -Busy -Message 'Genererer plan...'
        [System.Windows.Forms.Application]::DoEvents()

        Ensure-EbgGraphContext
        [System.Windows.Forms.Application]::DoEvents()

        Write-EbgStatus -Busy -Message 'Plan: analyserer tenant, konti, gruppe og Conditional Access...'
        [System.Windows.Forms.Application]::DoEvents()
        $plan = New-EbgPlanObject -Config $config -Discovery $sync.State.Discovery
        [System.Windows.Forms.Application]::DoEvents()

        if (-not $sync.State.OutputFolder) {
            $sync.State.OutputFolder = New-EbgOutputFolder -TenantId $plan.TenantId
        }
        $plan.OutputFolder = $sync.State.OutputFolder
        $plan.HandoffPath = Join-Path $sync.State.OutputFolder 'handoff.html'

        Write-EbgStatus -Busy -Message 'Plan: gemmer plan.json...'
        [System.Windows.Forms.Application]::DoEvents()
        Export-EbgJsonSafe -InputObject $plan -Path (Join-Path $sync.State.OutputFolder 'plan.json') -Depth 30 | Out-Null

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
FIDO2/passkey method policy: $($plan.Fido2AuthenticationMethodPolicyStatus)
Registration campaign: $($plan.RegistrationCampaignStatus)
Regular SSPR group: $($plan.RegularSSPRGroupName) / $($plan.RegularSSPRGroupStatus)
Regular SSPR rule: $($plan.RegularSSPRGroupRule)
Regular SSPR manual step: $($plan.RegularSSPRManualAction)

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
        $sync.WPFPlanText.Text = $text
        Invoke-EbgWPFButton -Name 'WPFStepPlan'
        Write-EbgStatus -Message 'Plan er genereret.'
    }
    catch {
        $message = ConvertTo-EbgRedactedError -ErrorRecord $_
        Write-EbgLog -Level ERROR -Message $message
        Write-EbgStatus -Message 'Plan fejlede.'
        [System.Windows.MessageBox]::Show($message, $sync.App.Name, 'OK', 'Error') | Out-Null
    }
    finally {
        $sync.UI.ProcessRunning = $false
        if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $false }
        if ($sync.WPFBuildPlan) { $sync.WPFBuildPlan.IsEnabled = $true }
        Update-EbgUIState | Out-Null
    }
}
