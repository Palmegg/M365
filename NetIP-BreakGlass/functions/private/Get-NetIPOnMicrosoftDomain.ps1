function Get-NetIPOnMicrosoftDomain {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Organization)

    $domains = @(Get-NetIPObjectPropertyValue -InputObject $Organization -Name 'verifiedDomains')
    $default = $domains | Where-Object { $_.isDefault -eq $true -and $_.name -like '*.onmicrosoft.com' } | Select-Object -First 1
    if ($default) { return [string] $default.name }
    $any = $domains | Where-Object { $_.name -like '*.onmicrosoft.com' } | Select-Object -First 1
    if ($any) { return [string] $any.name }
    throw 'Kunne ikke finde tenantens .onmicrosoft.com domæne.'
}
