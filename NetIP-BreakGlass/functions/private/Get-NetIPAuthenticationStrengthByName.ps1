function Get-NetIPAuthenticationStrengthByName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $DisplayName)

    if ($sync.App.Mock) {
        if ($DisplayName -eq $sync.configs.appsettings.authenticationStrengthName) {
            return $null
        }
        return $null
    }

    $filter = [uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
    $policies = @(Get-NetIPGraphCollection -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/authenticationStrength/policies?`$filter=$filter")
    return $policies | Select-Object -First 1
}
