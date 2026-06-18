function New-NetIPTemporaryAccessPass {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $User,
        [int] $LifetimeInMinutes = 120,
        [bool] $IsUsableOnce = $true,
        [Parameter(Mandatory)][bool] $Apply
    )

    $userId = [string](Get-NetIPObjectPropertyValue -InputObject $User -Name 'id')
    $upn = [string](Get-NetIPObjectPropertyValue -InputObject $User -Name 'userPrincipalName')
    if ([string]::IsNullOrWhiteSpace($userId)) { throw "Kan ikke oprette TAP for $upn, fordi brugeren mangler Object ID." }

    if (-not $Apply -or $sync.App.Mock) {
        return [pscustomobject]@{
            id = 'planned-tap'
            UserPrincipalName = $upn
            temporaryAccessPass = if ($Apply) { 'MOCK-TAP-12345678' } else { '' }
            lifetimeInMinutes = $LifetimeInMinutes
            isUsableOnce = $IsUsableOnce
            createdDateTime = (Get-Date).ToString('o')
            Status = if ($Apply) { 'Created' } else { 'PlannedCreate' }
        }
    }

    Write-NetIPLog -Message "Opretter Temporary Access Pass for $upn (one-time use: $IsUsableOnce, lifetime: $LifetimeInMinutes minutter)."
    $body = @{
        lifetimeInMinutes = $LifetimeInMinutes
        isUsableOnce = $IsUsableOnce
    }
    $created = Invoke-NetIPGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$userId/authentication/temporaryAccessPassMethods" -Body $body
    $created | Add-Member -MemberType NoteProperty -Name UserPrincipalName -Value $upn -Force
    $created | Add-Member -MemberType NoteProperty -Name lifetimeInMinutes -Value $LifetimeInMinutes -Force
    $created | Add-Member -MemberType NoteProperty -Name isUsableOnce -Value $IsUsableOnce -Force
    $created | Add-Member -MemberType NoteProperty -Name Status -Value 'Created' -Force
    return $created
}
