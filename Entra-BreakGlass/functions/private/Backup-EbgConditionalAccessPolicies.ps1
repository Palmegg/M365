function Backup-EbgConditionalAccessPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]] $Policies,
        [Parameter(Mandatory)][string] $OutputFolder
    )

    Write-EbgLog -Message "Backupper $(@($Policies).Count) Conditional Access policies til ca-policies-before.json..."
    $safePolicies = @()
    foreach ($policy in @($Policies)) {
        $safePolicies += [ordered]@{
            id              = [string](Get-EbgObjectPropertyValue -InputObject $policy -Name 'id')
            displayName     = [string](Get-EbgObjectPropertyValue -InputObject $policy -Name 'displayName')
            state           = [string](Get-EbgObjectPropertyValue -InputObject $policy -Name 'state')
            createdDateTime = Get-EbgObjectPropertyValue -InputObject $policy -Name 'createdDateTime'
            modifiedDateTime = Get-EbgObjectPropertyValue -InputObject $policy -Name 'modifiedDateTime'
            conditions      = ConvertTo-EbgPlainHashtable -InputObject (Get-EbgObjectPropertyValue -InputObject $policy -Name 'conditions') -MaxDepth 12
            grantControls   = ConvertTo-EbgPlainHashtable -InputObject (Get-EbgObjectPropertyValue -InputObject $policy -Name 'grantControls') -MaxDepth 12
            sessionControls = ConvertTo-EbgPlainHashtable -InputObject (Get-EbgObjectPropertyValue -InputObject $policy -Name 'sessionControls') -MaxDepth 12
        }
    }
    $path = Export-EbgJsonSafe -InputObject $safePolicies -Path (Join-Path $OutputFolder 'ca-policies-before.json') -Depth 20
    Write-EbgLog -Level PASS -Message "Conditional Access backup gemt: $path"
    return $path
}
