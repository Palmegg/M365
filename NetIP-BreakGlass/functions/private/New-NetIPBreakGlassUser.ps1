function New-NetIPBreakGlassUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][string] $UserPrincipalName,
        [Parameter(Mandatory)][string] $Password
    )

    if ($sync.App.Mock) {
        return [pscustomobject]@{ id = "mock-$($UserPrincipalName.Split('@')[0])"; displayName = $DisplayName; userPrincipalName = $UserPrincipalName; accountEnabled = $true; EnsureStatus = 'Created' }
    }
    $mailNickname = ($UserPrincipalName.Split('@')[0] -replace '[^A-Za-z0-9]', '')
    $body = @{
        accountEnabled    = $true
        displayName       = $DisplayName
        mailNickname      = $mailNickname
        userPrincipalName = $UserPrincipalName
        passwordProfile   = @{
            forceChangePasswordNextSignIn = $false
            password = $Password
        }
    }
    Invoke-NetIPGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/users' -Body $body | Out-Null
    $user = Get-NetIPUserByUpn -UserPrincipalName $UserPrincipalName
    $user | Add-Member -MemberType NoteProperty -Name EnsureStatus -Value 'Created' -Force
    return $user
}
