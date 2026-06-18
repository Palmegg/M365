function Get-EbgUserByUpn {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $UserPrincipalName)

    if ($sync.App.Mock) {
        if ($UserPrincipalName -like 'horse.unit@*') {
            return [pscustomobject]@{ id = 'mock-user-1'; displayName = 'Horse Unit'; userPrincipalName = $UserPrincipalName; accountEnabled = $true }
        }
        return $null
    }
    try {
        return Invoke-EbgGraphRequest -Method GET -Uri ("https://graph.microsoft.com/v1.0/users/{0}?`$select=id,displayName,userPrincipalName,accountEnabled" -f [uri]::EscapeDataString($UserPrincipalName)) -SuppressNotFoundLog
    }
    catch {
        if ([string]$_ -match '404|Request_ResourceNotFound|Resource .* does not exist') { return $null }
        throw
    }
}