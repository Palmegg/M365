function Save-EbgResultJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)][string] $OutputFolder
    )

    return Export-EbgJsonSafe -InputObject $Result -Path (Join-Path $OutputFolder 'result.json') -Depth 40
}