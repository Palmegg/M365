function ConvertTo-EbgPlainHashtable {
    [CmdletBinding()]
    param(
        [AllowNull()] $InputObject,
        [int] $Depth = 0,
        [int] $MaxDepth = 20
    )

    if ($null -eq $InputObject) { return $null }
    if ($Depth -ge $MaxDepth) { return ([string]$InputObject) }
    if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive) { return $InputObject }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[[string]$key] = ConvertTo-EbgPlainHashtable -InputObject $InputObject[$key] -Depth ($Depth + 1) -MaxDepth $MaxDepth
        }
        return $hash
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [System.Collections.IDictionary])) {
        $items = @()
        foreach ($item in $InputObject) { $items += ConvertTo-EbgPlainHashtable -InputObject $item -Depth ($Depth + 1) -MaxDepth $MaxDepth }
        return $items
    }
    $hash = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $hash[$property.Name] = ConvertTo-EbgPlainHashtable -InputObject $property.Value -Depth ($Depth + 1) -MaxDepth $MaxDepth
    }
    return $hash
}
