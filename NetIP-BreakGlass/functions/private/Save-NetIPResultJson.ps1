function Save-NetIPResultJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)][string] $OutputFolder
    )

    return Export-NetIPJsonSafe -InputObject $Result -Path (Join-Path $OutputFolder 'result.json') -Depth 40
}
