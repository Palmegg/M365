function Remove-EbgTemporaryAccessPassMethods {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]] $Users,
        [Parameter(Mandatory)][bool] $Apply
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($user in $Users) {
        $userId = [string](Get-EbgObjectPropertyValue -InputObject $user -Name 'id')
        $upn = [string](Get-EbgObjectPropertyValue -InputObject $user -Name 'userPrincipalName')
        if ([string]::IsNullOrWhiteSpace($userId)) { continue }

        $methods = @(Get-EbgTemporaryAccessPassMethods -User $user)
        if ($methods.Count -lt 1) {
            $results.Add([pscustomobject]@{ UserPrincipalName = $upn; MethodId = ''; Status = 'NotFound' })
            continue
        }

        foreach ($method in $methods) {
            $methodId = [string](Get-EbgObjectPropertyValue -InputObject $method -Name 'id')
            if (-not $Apply -or $sync.App.Mock) {
                $results.Add([pscustomobject]@{ UserPrincipalName = $upn; MethodId = $methodId; Status = if($Apply){'Deleted'}else{'PlannedDelete'} })
                continue
            }
            Invoke-EbgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$userId/authentication/temporaryAccessPassMethods/$methodId" | Out-Null
            $results.Add([pscustomobject]@{ UserPrincipalName = $upn; MethodId = $methodId; Status = 'Deleted' })
            Write-EbgLog -Level PASS -Message "Temporary Access Pass slettet for $upn."
        }
    }
    return @($results)
}