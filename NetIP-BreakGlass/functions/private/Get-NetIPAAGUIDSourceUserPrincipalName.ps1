function Get-NetIPAAGUIDSourceUserPrincipalName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable] $Config)

    $tenant = Get-NetIPTenantInfo
    return $sync.Form.Dispatcher.Invoke([func[string]]{
        $selectedIndex = if ($sync.WPFAAGUIDSourceUser) { [int]$sync.WPFAAGUIDSourceUser.SelectedIndex } else { 0 }
        switch ($selectedIndex) {
            0 { ConvertTo-BreakGlassUpn -Prefix $Config.UserPrefix1 -OnMicrosoftDomain $tenant.OnMicrosoftDomain }
            1 { ConvertTo-BreakGlassUpn -Prefix $Config.UserPrefix2 -OnMicrosoftDomain $tenant.OnMicrosoftDomain }
            default {
                $custom = if ($sync.WPFAAGUIDCustomUser) { $sync.WPFAAGUIDCustomUser.Text.Trim() } else { '' }
                if ([string]::IsNullOrWhiteSpace($custom)) { throw 'Angiv en custom UPN, eller vælg Account 1/2 som AAGUID kildebruger.' }
                $custom
            }
        }
    })
}
