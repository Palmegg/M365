function Invoke-NetIPDiscovery {
    [CmdletBinding()]
    param()

    if (-not $sync.State.GraphConnected -and -not $sync.App.Mock) {
        [System.Windows.MessageBox]::Show("Du skal først forbinde til Microsoft Graph under trinnet 'Forbind'.", $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }
    $config = Get-NetIPConfigFromUI
    Invoke-NetIPRunspace -ArgumentList @($config) -ScriptBlock {
        param($config)
        Write-NetIPStatus -Busy -Message 'Kører discovery...'
        $tenant = Get-NetIPTenantInfo
        $upn1 = ConvertTo-NetIPBreakGlassUpn -Prefix $config.UserPrefix1 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        $upn2 = ConvertTo-NetIPBreakGlassUpn -Prefix $config.UserPrefix2 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        $user1 = Get-NetIPUserByUpn -UserPrincipalName $upn1
        $user2 = Get-NetIPUserByUpn -UserPrincipalName $upn2
        $group = Get-NetIPGroupByDisplayName -DisplayName $config.GroupName
        $policies = @(Get-NetIPConditionalAccessPolicies)
        $already = @()
        if ($group -and $group.id) {
            foreach ($policy in $policies) {
                $excludeGroups = @(Get-NetIPObjectPropertyValue -InputObject (Get-NetIPObjectPropertyValue -InputObject (Get-NetIPObjectPropertyValue -InputObject $policy -Name 'conditions') -Name 'users') -Name 'excludeGroups')
                if ($excludeGroups -contains $group.id) { $already += $policy }
            }
        }
        $discovery = [pscustomobject]@{
            Tenant = $tenant
            User1 = $user1
            User2 = $user2
            Group = $group
            CAPolicies = $policies
            CAPoliciesAlreadyExcluded = $already
            TargetUPN1 = $upn1
            TargetUPN2 = $upn2
            Timestamp = (Get-Date).ToString('o')
        }
        $sync.State.Discovery = $discovery
        $summary = "User1: $(if($user1){'findes'}else{'mangler'}); User2: $(if($user2){'findes'}else{'mangler'}); Gruppe: $(if($group){'findes'}else{'mangler'}); CA policies: $($policies.Count)"
        $lines = @(
            "Tenant: $($tenant.TenantDisplayName) / $($tenant.TenantId)",
            "Domain: $($tenant.OnMicrosoftDomain)",
            "Target user 1: $upn1 - $(if($user1){'Findes'}else{'Mangler'})",
            "Target user 2: $upn2 - $(if($user2){'Findes'}else{'Mangler'})",
            "Group $($config.GroupName): $(if($group){'Findes'}else{'Mangler'})",
            "Conditional Access policies: $($policies.Count)",
            "Policies der allerede ekskluderer gruppen: $($already.Count)"
        )
        $sync.Form.Dispatcher.BeginInvoke([action]{
            $sync.WPFDiscoverySummary.Text = $summary
            $sync.WPFDiscoveryList.Text = ($lines -join [Environment]::NewLine)
            Invoke-NetIPWPFButton -Name 'WPFStepDiscovery'
        }) | Out-Null
        Write-NetIPStatus -Message 'Discovery er færdig.'
    }
}
