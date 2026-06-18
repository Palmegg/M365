function Remove-NetIPTemporaryAccessPassMethods {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]] $Users,
        [Parameter(Mandatory)][bool] $Apply
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($user in $Users) {
        $userId = [string](Get-NetIPObjectPropertyValue -InputObject $user -Name 'id')
        $upn = [string](Get-NetIPObjectPropertyValue -InputObject $user -Name 'userPrincipalName')
        if ([string]::IsNullOrWhiteSpace($userId)) { continue }

        $methods = @(Get-NetIPTemporaryAccessPassMethods -User $user)
        if ($methods.Count -lt 1) {
            $results.Add([pscustomobject]@{ UserPrincipalName = $upn; MethodId = ''; Status = 'NotFound' })
            continue
        }

        foreach ($method in $methods) {
            $methodId = [string](Get-NetIPObjectPropertyValue -InputObject $method -Name 'id')
            if (-not $Apply -or $sync.App.Mock) {
                $results.Add([pscustomobject]@{ UserPrincipalName = $upn; MethodId = $methodId; Status = if($Apply){'Deleted'}else{'PlannedDelete'} })
                continue
            }
            Invoke-NetIPGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$userId/authentication/temporaryAccessPassMethods/$methodId" | Out-Null
            $results.Add([pscustomobject]@{ UserPrincipalName = $upn; MethodId = $methodId; Status = 'Deleted' })
            Write-NetIPLog -Level PASS -Message "Temporary Access Pass slettet for $upn."
        }
    }
    return @($results)
}
