function Get-NetIPGraphCollection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Uri)

    $items = @()
    $next = $Uri
    while ($next) {
        $response = Invoke-NetIPGraphRequest -Method GET -Uri $next
        $value = Get-NetIPObjectPropertyValue -InputObject $response -Name 'value'
        if ($value) { $items += @($value) }
        $next = Get-NetIPObjectPropertyValue -InputObject $response -Name '@odata.nextLink'
    }
    return $items
}
