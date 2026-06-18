function ConvertTo-BreakGlassUpn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Prefix,
        [Parameter(Mandatory)][string] $OnMicrosoftDomain
    )

    $cleanPrefix = $Prefix.Trim()
    if ([string]::IsNullOrWhiteSpace($cleanPrefix)) { throw 'UPN prefix må ikke være tomt.' }
    if ($cleanPrefix -match '@') { throw 'Angiv kun UPN prefix, ikke et fuldt UPN.' }
    if ($cleanPrefix -notmatch '^[A-Za-z0-9._-]+$') { throw 'UPN prefix må kun indeholde bogstaver, tal, punktum, bindestreg og underscore.' }
    return ('{0}@{1}' -f $cleanPrefix, $OnMicrosoftDomain.ToLowerInvariant())
}