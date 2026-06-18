function ConvertTo-EbgNeutralUserPrefix {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $DisplayName)

    $prefix = $DisplayName.Trim().ToLowerInvariant()
    $prefix = [regex]::Replace($prefix, '[^a-z0-9]+', '.')
    $prefix = $prefix.Trim('.')
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        throw 'Kunne ikke lave et neutralt UPN prefix fra display name.'
    }
    return $prefix
}