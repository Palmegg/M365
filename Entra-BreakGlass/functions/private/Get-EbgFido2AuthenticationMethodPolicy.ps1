function Get-EbgFido2AuthenticationMethodPolicy {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) {
        return [pscustomobject]@{
            '@odata.type' = '#microsoft.graph.fido2AuthenticationMethodConfiguration'
            id = 'Fido2'
            state = 'disabled'
            isSelfServiceRegistrationAllowed = $false
            includeTargets = @()
            passkeyProfiles = @(
                [pscustomobject]@{
                    id = '00000000-0000-0000-0000-000000000001'
                    name = 'Default passkey profile'
                }
            )
        }
    }

    return Invoke-EbgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2'
}
