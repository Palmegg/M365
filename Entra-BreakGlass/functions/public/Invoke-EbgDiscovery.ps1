function Invoke-EbgDiscovery {
    [CmdletBinding()]
    param()

    if (-not $sync.State.GraphConnected -and -not $sync.App.Mock) {
        [System.Windows.MessageBox]::Show("Du skal først forbinde til Microsoft Graph under trinnet 'Forbind'.", $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }
    $config = Get-EbgConfigFromUI
    Invoke-EbgRunspace -ArgumentList @($config) -ScriptBlock {
        param($config)
        Write-EbgStatus -Busy -Message 'Kører discovery...'
        Ensure-EbgGraphContext
        Write-EbgStatus -Busy -Message 'Discovery: henter tenant information...'
        $tenant = Get-EbgTenantInfo
        $upn1 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix1 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        $upn2 = ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix2 -OnMicrosoftDomain $tenant.OnMicrosoftDomain
        Write-EbgStatus -Busy -Message "Discovery: tjekker target user 1 ($upn1)..."
        $user1 = Get-EbgUserByUpn -UserPrincipalName $upn1
        Write-EbgStatus -Busy -Message "Discovery: tjekker target user 2 ($upn2)..."
        $user2 = Get-EbgUserByUpn -UserPrincipalName $upn2
        Write-EbgStatus -Busy -Message "Discovery: tjekker security group ($($config.GroupName))..."
        $group = Get-EbgGroupByDisplayName -DisplayName $config.GroupName
        Write-EbgStatus -Busy -Message 'Discovery: henter Conditional Access policies...'
        $policies = @(Get-EbgConditionalAccessPolicies)
        Write-EbgStatus -Busy -Message 'Discovery: henter aktive Global Administrator assignments...'
        $activeGlobalAdmins = @(Get-EbgActiveGlobalAdministrators)
        Write-EbgStatus -Busy -Message 'Discovery: analyserer CA exclusions...'
        $already = @()
        $groupId = [string](Get-EbgObjectPropertyValue -InputObject $group -Name 'id')
        if ($group -and $groupId) {
            foreach ($policy in $policies) {
                $excludeGroups = @(Get-EbgObjectPropertyValue -InputObject (Get-EbgObjectPropertyValue -InputObject (Get-EbgObjectPropertyValue -InputObject $policy -Name 'conditions') -Name 'users') -Name 'excludeGroups')
                if ($excludeGroups -contains $groupId) { $already += $policy }
            }
        }
        $discovery = [pscustomobject]@{
            Tenant = $tenant
            User1 = $user1
            User2 = $user2
            Group = $group
            CAPolicies = $policies
            CAPoliciesAlreadyExcluded = $already
            ActiveGlobalAdministrators = $activeGlobalAdmins
            TargetUPN1 = $upn1
            TargetUPN2 = $upn2
            Timestamp = (Get-Date).ToString('o')
        }
        $sync.State.Discovery = $discovery
        $summary = "Aktive Global Admins: $($activeGlobalAdmins.Count); Target user1: $(if($user1){'findes'}else{'mangler'}); Target user2: $(if($user2){'findes'}else{'mangler'}); Gruppe: $(if($group){'findes'}else{'mangler'}); CA policies: $($policies.Count)"
        $userMissingSeverity = if ($config.CreateUsers) { 'Warning' } else { 'Bad' }
        $groupMissingSeverity = if ($config.CreateGroup) { 'Warning' } else { 'Bad' }
        $excludedSeverity = if ($policies.Count -eq 0) {
            'Good'
        }
        elseif ($already.Count -eq $policies.Count) {
            'Good'
        }
        elseif ($config.PatchCAPolicies) {
            'Warning'
        }
        else {
            'Bad'
        }
        $summarySeverity = if ((-not $user1 -and -not $config.CreateUsers) -or (-not $user2 -and -not $config.CreateUsers) -or (-not $group -and -not $config.CreateGroup) -or $excludedSeverity -eq 'Bad') {
            'Bad'
        }
        elseif (-not $user1 -or -not $user2 -or -not $group -or $excludedSeverity -eq 'Warning') {
            'Warning'
        }
        else {
            'Good'
        }
        $lines = @(
            [pscustomobject]@{ Severity = 'Info'; Text = "Tenant: $($tenant.TenantDisplayName) / $($tenant.TenantId)" },
            [pscustomobject]@{ Severity = 'Info'; Text = "Domain: $($tenant.OnMicrosoftDomain)" },
            [pscustomobject]@{ Severity = if($user1){'Good'}else{$userMissingSeverity}; Text = "Target user 1: $upn1 - $(if($user1){'Findes'}elseif($config.CreateUsers){'Mangler - planlagt oprettet'}else{'Mangler - oprettelse er fravalgt'})" },
            [pscustomobject]@{ Severity = if($user2){'Good'}else{$userMissingSeverity}; Text = "Target user 2: $upn2 - $(if($user2){'Findes'}elseif($config.CreateUsers){'Mangler - planlagt oprettet'}else{'Mangler - oprettelse er fravalgt'})" },
            [pscustomobject]@{ Severity = if($group){'Good'}else{$groupMissingSeverity}; Text = "Group $($config.GroupName): $(if($group){'Findes'}elseif($config.CreateGroup){'Mangler - planlagt oprettet'}else{'Mangler - oprettelse er fravalgt'})" },
            [pscustomobject]@{ Severity = if($activeGlobalAdmins.Count -gt 0){'Info'}else{'Warning'}; Text = "Aktive direkte Global Administrator brugere: $($activeGlobalAdmins.Count)" },
            [pscustomobject]@{ Severity = 'Info'; Text = "Conditional Access policies: $($policies.Count)" },
            [pscustomobject]@{ Severity = $excludedSeverity; Text = "Policies der allerede ekskluderer gruppen: $($already.Count) af $($policies.Count)" }
        )
        foreach ($admin in $activeGlobalAdmins) {
            $lines += [pscustomobject]@{
                Severity = 'Info'
                Text = " - GA: $([string](Get-EbgObjectPropertyValue -InputObject $admin -Name 'displayName')) <$([string](Get-EbgObjectPropertyValue -InputObject $admin -Name 'userPrincipalName'))>"
            }
        }
        $sync.Form.Dispatcher.Invoke([System.Action]{
            $sync.WPFDiscoverySummary.Text = $summary
            $sync.WPFDiscoverySummary.Foreground = switch ($summarySeverity) {
                'Good' { [System.Windows.Media.Brushes]::ForestGreen }
                'Warning' { [System.Windows.Media.Brushes]::DarkOrange }
                'Bad' { [System.Windows.Media.Brushes]::Firebrick }
                default { [System.Windows.Media.Brushes]::Black }
            }
            $document = New-Object System.Windows.Documents.FlowDocument
            foreach ($line in $lines) {
                $paragraph = New-Object System.Windows.Documents.Paragraph
                $prefix = switch ($line.Severity) {
                    'Good' { '[OK] ' }
                    'Warning' { '[ADVARSEL] ' }
                    'Bad' { '[FEJL] ' }
                    default { '[INFO] ' }
                }
                $run = New-Object System.Windows.Documents.Run ($prefix + $line.Text)
                $run.Foreground = switch ($line.Severity) {
                    'Good' { [System.Windows.Media.Brushes]::ForestGreen }
                    'Warning' { [System.Windows.Media.Brushes]::DarkOrange }
                    'Bad' { [System.Windows.Media.Brushes]::Firebrick }
                    default { [System.Windows.Media.Brushes]::SlateGray }
                }
                $run.FontWeight = if ($line.Severity -eq 'Info') { [System.Windows.FontWeights]::Normal } else { [System.Windows.FontWeights]::SemiBold }
                [void]$paragraph.Inlines.Add($run)
                [void]$document.Blocks.Add($paragraph)
            }
            $sync.WPFDiscoveryList.Document = $document
            Invoke-EbgWPFButton -Name 'WPFStepDiscovery'
        })
        Write-EbgStatus -Message 'Discovery er færdig.'
    }
}
