function Write-NetIPStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [switch] $Busy
    )

    Write-NetIPLog -Message $Message
    if ($sync.WPFStatusText) {
        $callback = [System.Action[string,bool]]{
            param($statusMessage, $isBusy)
            $sync.WPFStatusText.Text = $statusMessage
            $sync.WPFProgressBar.IsIndeterminate = $isBusy
        }
        $sync.WPFStatusText.Dispatcher.BeginInvoke($callback, $Message, [bool]$Busy) | Out-Null
    }
}
