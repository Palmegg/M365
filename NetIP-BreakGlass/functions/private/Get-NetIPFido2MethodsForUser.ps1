function Get-NetIPFido2MethodsForUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $UserPrincipalName)

    if ($sync.App.Mock) {
        return @(
            [pscustomobject]@{
                id = 'mock-fido2-1'
                displayName = 'YubiKey Security Key NFC'
                model = 'Security Key NFC by Yubico'
                aaGuid = 'a4e9fc6d-4cbe-4758-b8ba-37598bb5bbaa'
                attestationLevel = 'attested'
                passkeyType = 'deviceBound'
                createdDateTime = (Get-Date).ToString('o')
            }
        )
    }

    $encoded = [uri]::EscapeDataString($UserPrincipalName)
    return Get-NetIPGraphCollection -Uri "https://graph.microsoft.com/v1.0/users/$encoded/authentication/fido2Methods"
}
