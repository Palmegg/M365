function Close-EbgApplication {
    [CmdletBinding()]
    param()

    if ($sync.UI.ProcessRunning -and -not [bool]$sync.UI.AllowForcedClose) {
        $answer = [System.Windows.MessageBox]::Show(
            'Der kører en baggrundsopgave. Vil du stoppe opgaven og lukke configuratoren?',
            $sync.App.Name,
            'YesNo',
            'Warning'
        )
        if ($answer -ne 'Yes') {
            return
        }
        $sync.UI.AllowForcedClose = $true
        $sync.UI.StopRequested = $true
        Write-EbgStatus -Busy -Message 'Stopper baggrundsopgave og lukker configuratoren...'
    }

    if ($sync.Form) {
        $sync.Form.Close()
    }
}
