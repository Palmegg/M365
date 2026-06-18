function ConvertTo-EbgPlainHashtable {
    [CmdletBinding()]
    param([AllowNull()] $InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive) { return $InputObject }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [System.Collections.IDictionary])) {
        $items = @()
        foreach ($item in $InputObject) { $items += ConvertTo-EbgPlainHashtable -InputObject $item }
        return $items
    }
    $hash = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $hash[$property.Name] = ConvertTo-EbgPlainHashtable -InputObject $property.Value
    }
    return $hash
}