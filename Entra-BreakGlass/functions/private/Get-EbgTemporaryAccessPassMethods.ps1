function Get-EbgTemporaryAccessPassMethods {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $User)

    $userId = [string](Get-EbgObjectPropertyValue -InputObject $User -Name 'id')
    $upn = [string](Get-EbgObjectPropertyValue -InputObject $User -Name 'userPrincipalName')
    if ([string]::IsNullOrWhiteSpace($userId)) { return @() }

    if ($sync.App.Mock) {
        return @(
            [pscustomobject]@{
                id = 'mock-existing-tap'
                UserPrincipalName = $upn
                createdDateTime = (Get-Date).AddMinutes(-10).ToString('o')
                lifetimeInMinutes = 120
                isUsableOnce = $true
            }
        )
    }

    return @(Get-EbgGraphCollection -Uri "https://graph.microsoft.com/v1.0/users/$userId/authentication/temporaryAccessPassMethods" | ForEach-Object {
        $_ | Add-Member -MemberType NoteProperty -Name UserPrincipalName -Value $upn -Force
        $_
    })
}