function Backup-NetIPConditionalAccessPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]] $Policies,
        [Parameter(Mandatory)][string] $OutputFolder
    )

    return Export-NetIPJsonSafe -InputObject $Policies -Path (Join-Path $OutputFolder 'ca-policies-before.json') -Depth 50
}
