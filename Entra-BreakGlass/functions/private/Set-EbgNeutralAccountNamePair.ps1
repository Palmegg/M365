function Set-EbgNeutralAccountNamePair {
    [CmdletBinding()]
    param([switch] $Random)

    $pairs = @($sync.configs.defaults.neutralNamePairs)
    if ($pairs.Count -lt 1) {
        throw 'Der er ingen neutrale navnepar i defaults.json.'
    }

    $nextIndex = if ($Random) {
        Get-Random -Minimum 0 -Maximum $pairs.Count
    }
    else {
        ([int]$sync.State.NeutralNameIndex + 1) % $pairs.Count
    }
    $sync.State.NeutralNameIndex = $nextIndex
    $pair = $pairs[$nextIndex]

    $account1 = [string](Get-EbgObjectPropertyValue -InputObject $pair -Name 'account1')
    $account2 = [string](Get-EbgObjectPropertyValue -InputObject $pair -Name 'account2')
    if ([string]::IsNullOrWhiteSpace($account1) -or [string]::IsNullOrWhiteSpace($account2)) {
        throw "Navnepar nummer $($nextIndex + 1) er ikke udfyldt korrekt."
    }

    $sync.WPFDisplayName1.Text = $account1
    $sync.WPFDisplayName2.Text = $account2
    $sync.WPFUserPrefix1.Text = ConvertTo-EbgNeutralUserPrefix -DisplayName $account1
    $sync.WPFUserPrefix2.Text = ConvertTo-EbgNeutralUserPrefix -DisplayName $account2
    if ($sync.WPFPhase2UserPrefix1) { $sync.WPFPhase2UserPrefix1.Text = $sync.WPFUserPrefix1.Text }
    if ($sync.WPFPhase2UserPrefix2) { $sync.WPFPhase2UserPrefix2.Text = $sync.WPFUserPrefix2.Text }

    $action = if ($Random) { 'Valgte tilfældige neutrale kontonavne' } else { 'Skiftede neutrale kontonavne' }
    Write-EbgLog -Message "${action} til: $account1 / $account2"
    Update-EbgUIState
}
