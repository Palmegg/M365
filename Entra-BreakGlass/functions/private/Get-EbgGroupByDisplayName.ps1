function Get-EbgGroupByDisplayName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $DisplayName)

    if ($sync.App.Mock) {
        if ($DisplayName -eq 'CA-BreakGlass-Exclude') {
            return $null
        }
        return $null
    }
    $filter = [uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
    return Get-EbgGraphCollection -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,description,mailNickname,securityEnabled,mailEnabled,groupTypes,membershipRule,membershipRuleProcessingState" | Select-Object -First 1
}
