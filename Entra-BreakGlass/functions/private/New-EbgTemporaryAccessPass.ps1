function New-EbgTemporaryAccessPass {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $User,
        [int] $LifetimeInMinutes = 120,
        [bool] $IsUsableOnce = $false,
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

    $maxAttempts = 20
    $delaySeconds = 15
    $lastError = $null
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Write-EbgStatus -Busy -Message "Phase 1a step 6/12: opretter TAP for $upn (forsøg $attempt/$maxAttempts)..."
            [System.Windows.Forms.Application]::DoEvents()
            if ($attempt -gt 1 -and -not [string]::IsNullOrWhiteSpace($upn)) {
                $refreshedUser = Get-EbgUserByUpn -UserPrincipalName $upn
                $refreshedUserId = [string](Get-EbgObjectPropertyValue -InputObject $refreshedUser -Name 'id')
                if (-not [string]::IsNullOrWhiteSpace($refreshedUserId)) {
                    $userId = $refreshedUserId
                }
            }
            $created = Invoke-EbgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$userId/authentication/temporaryAccessPassMethods" -Body $body -SuppressErrorLog:($attempt -lt $maxAttempts)
            break
        }
        catch {
            $lastError = $_
            $message = ConvertTo-EbgRedactedError -ErrorRecord $_
            $isAuthorizationDelay = $message -match '403 Forbidden|accessDenied|Request Authorization failed'
            $isBackendDelay = $message -match '404 Not Found|resourceNotFound|Request_ResourceNotFound|Resource .* does not exist|reference-property objects are not present'
            $isRetryable = $isAuthorizationDelay -or $isBackendDelay
            if (-not $isRetryable -or $attempt -ge $maxAttempts) {
                if ($isAuthorizationDelay) {
                    throw "Kunne ikke oprette Temporary Access Pass for $upn efter $maxAttempts forsøg over ca. $([int](($maxAttempts - 1) * $delaySeconds / 60)) minutter. Microsoft Graph afviste requesten med 403/accessDenied. Kontroller at tokenet har UserAuthMethod-TAP.ReadWrite.All med admin consent, at operatoren har Authentication Administrator eller Privileged Authentication Administrator, og at TAP authentication method policy er enabled."
                }
                if ($isBackendDelay) {
                    throw "Kunne ikke oprette Temporary Access Pass for $upn efter $maxAttempts forsøg over ca. $([int](($maxAttempts - 1) * $delaySeconds / 60)) minutter. Brugeren findes i directory, men Microsoft Graph authentication methods backend returnerer stadig 404/resourceNotFound. Vent et par minutter og kør Phase 1a igen; eksisterende brugere og gruppen genbruges."
                }
                throw
            }

            $reason = if ($isBackendDelay) { '404/resourceNotFound' } else { '403/accessDenied' }
            Write-EbgLog -Level WARN -Message "TAP for $upn blev afvist med $reason på forsøg $attempt/$maxAttempts. Venter $delaySeconds sekunder og prøver igen; nye brugere kan være forsinket i authentication methods backend."
            Write-EbgStatus -Busy -Message "Phase 1a step 6/12: venter på TAP backend for $upn ($attempt/$maxAttempts)..."
            $until = (Get-Date).AddSeconds($delaySeconds)
            while ((Get-Date) -lt $until) {
                Start-Sleep -Milliseconds 250
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
    }

    if (-not $created) {
        if ($lastError) { throw $lastError }
        throw "Kunne ikke oprette Temporary Access Pass for $upn. Ukendt fejl."
    }

    $created | Add-Member -MemberType NoteProperty -Name UserPrincipalName -Value $upn -Force
    $created | Add-Member -MemberType NoteProperty -Name lifetimeInMinutes -Value $LifetimeInMinutes -Force
    $created | Add-Member -MemberType NoteProperty -Name isUsableOnce -Value $IsUsableOnce -Force
    $created | Add-Member -MemberType NoteProperty -Name Status -Value 'Created' -Force
    return $created
}
