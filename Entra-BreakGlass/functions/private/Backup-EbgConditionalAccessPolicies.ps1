function Backup-EbgConditionalAccessPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]] $Policies,
        [Parameter(Mandatory)][string] $OutputFolder
    )

    return Export-EbgJsonSafe -InputObject $Policies -Path (Join-Path $OutputFolder 'ca-policies-before.json') -Depth 50
}