function Get-EbgAuthenticationMethodsPolicy {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) {
        return [pscustomobject]@{
            id = 'authenticationMethodsPolicy'
            registrationEnforcement = [pscustomobject]@{
                authenticationMethodsRegistrationCampaign = [pscustomobject]@{
                    state = 'enabled'
                    snoozeDurationInDays = 1
                    enforceRegistrationAfterAllowedSnoozes = $true
                    includeTargets = @(
                        [pscustomobject]@{
                            id = 'all_users'
                            targetType = 'group'
                            targetedAuthenticationMethod = 'microsoftAuthenticator'
                        }
                    )
                    excludeTargets = @()
                }
            }
        }
    }

    return Invoke-EbgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy'
}
