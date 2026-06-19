function Get-EbgGraphCollection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Uri)

    $items = @()
    $next = $Uri
    $page = 0
    $visited = @{}
    while ($next) {
        $page++
        if ($page -gt 50) {
            throw "Graph collection pagination stopped after 50 pages for URI: $Uri"
        }
        if ($visited.ContainsKey($next)) {
            throw "Graph collection pagination loop detected for URI: $next"
        }
        $visited[$next] = $true

        $response = Invoke-EbgGraphRequest -Method GET -Uri $next
        $value = Get-EbgObjectPropertyValue -InputObject $response -Name 'value'
        if ($value) { $items += @($value) }
        $next = Get-EbgObjectPropertyValue -InputObject $response -Name '@odata.nextLink'
        if ([string]::IsNullOrWhiteSpace([string]$next)) {
            $next = $null
        }
    }
    return $items
}
