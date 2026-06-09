function Get-NetIPConditionalAccessPolicies {
    [CmdletBinding()]
    param()

    if ($sync.App.Mock) {
        return @(
            [pscustomobject]@{ id='mock-ca-1'; displayName='CA001 Require MFA'; state='enabled'; conditions=[pscustomobject]@{ users=[pscustomobject]@{ includeUsers=@('All'); excludeGroups=@() } } },
            [pscustomobject]@{ id='mock-ca-2'; displayName='CA002 Block legacy'; state='enabled'; conditions=[pscustomobject]@{ users=[pscustomobject]@{ includeUsers=@('All'); excludeGroups=@('mock-existing') } } },
            [pscustomobject]@{ id='mock-ca-3'; displayName='CA003 Report only'; state='enabledForReportingButNotEnforced'; conditions=[pscustomobject]@{ users=[pscustomobject]@{ includeUsers=@('All'); excludeGroups=@() } } }
        )
    }
    return Get-NetIPGraphCollection -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies'
}
