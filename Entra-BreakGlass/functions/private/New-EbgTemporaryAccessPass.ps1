function New-EbgTemporaryAccessPass {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $User,
        [int] $LifetimeInMinutes = 120,
        [bool] $IsUsableOnce = $true,
        [Parameter(Mandatory)][bool] $Apply
    )

    $userId = [string](Get-EbgObjectPropertyValue -InputObject $User -Name 'id')
    $upn = [string](Get-EbgObjectPropertyValue -InputObject $User -Name 'userPrincipalName')
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

    Write-EbgLog -Message "Opretter Temporary Access Pass for $upn (one-time use: $IsUsableOnce, lifetime: $LifetimeInMinutes minutter)."
    $body = @{
        lifetimeInMinutes = $LifetimeInMinutes
        isUsableOnce = $IsUsableOnce
    }
    try {
        $created = Invoke-EbgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$userId/authentication/temporaryAccessPassMethods" -Body $body
    }
    catch {
        $message = ConvertTo-EbgRedactedError -ErrorRecord $_
        if ($message -match '403 Forbidden|accessDenied|Request Authorization failed') {
            throw "Kunne ikke oprette Temporary Access Pass for $upn. Microsoft Graph afviste requesten med 403/accessDenied. Hvis kontoen allerede har en privilegeret administratorrolle, kræver TAP-oprettelse typisk Privileged Authentication Administrator. Kør med en konto der har den rolle, eller fjern midlertidigt Global Administrator fra target-kontoen og kør Phase 1a igen. Nye runs opretter TAP før Global Administrator rollen tildeles."
        }
        throw
    }
    $created | Add-Member -MemberType NoteProperty -Name UserPrincipalName -Value $upn -Force
    $created | Add-Member -MemberType NoteProperty -Name lifetimeInMinutes -Value $LifetimeInMinutes -Force
    $created | Add-Member -MemberType NoteProperty -Name isUsableOnce -Value $IsUsableOnce -Force
    $created | Add-Member -MemberType NoteProperty -Name Status -Value 'Created' -Force
    return $created
}
