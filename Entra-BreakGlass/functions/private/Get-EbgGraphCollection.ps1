function Get-EbgGraphCollection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Uri)

    $items = @()
    $next = $Uri
    while ($next) {
        $response = Invoke-EbgGraphRequest -Method GET -Uri $next
        $value = Get-EbgObjectPropertyValue -InputObject $response -Name 'value'
        if ($value) { $items += @($value) }
        $next = Get-EbgObjectPropertyValue -InputObject $response -Name '@odata.nextLink'
    }
    return $items
}