function Get-NetIPUserByUpn {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $UserPrincipalName)

    if ($sync.App.Mock) {
        if ($UserPrincipalName -like 'BreakGlass01@*') {
            return [pscustomobject]@{ id = 'mock-user-1'; displayName = 'BreakGlass 01'; userPrincipalName = $UserPrincipalName; accountEnabled = $true }
        }
        return $null
    }
    try {
        return Invoke-NetIPGraphRequest -Method GET -Uri ("https://graph.microsoft.com/v1.0/users/{0}?`$select=id,displayName,userPrincipalName,accountEnabled" -f [uri]::EscapeDataString($UserPrincipalName)) -SuppressNotFoundLog
    }
    catch {
        if ([string]$_ -match '404|Request_ResourceNotFound|Resource .* does not exist') { return $null }
        throw
    }
}
