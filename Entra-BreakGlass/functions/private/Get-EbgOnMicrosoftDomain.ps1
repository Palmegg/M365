function Get-EbgOnMicrosoftDomain {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Organization)

    $domains = @(Get-EbgObjectPropertyValue -InputObject $Organization -Name 'verifiedDomains')
    $default = $domains | Where-Object {
        [bool](Get-EbgObjectPropertyValue -InputObject $_ -Name 'isDefault') -and
        [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'name') -like '*.onmicrosoft.com'
    } | Select-Object -First 1
    if ($default) { return [string](Get-EbgObjectPropertyValue -InputObject $default -Name 'name') }

    $any = $domains | Where-Object {
        [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'name') -like '*.onmicrosoft.com'
    } | Select-Object -First 1
    if ($any) { return [string](Get-EbgObjectPropertyValue -InputObject $any -Name 'name') }

    throw 'Kunne ikke finde tenantens .onmicrosoft.com domæne.'
}
