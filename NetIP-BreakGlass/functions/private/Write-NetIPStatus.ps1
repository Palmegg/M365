function Write-NetIPStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [switch] $Busy
    )

    Write-NetIPLog -Message $Message
    if ($sync.WPFStatusText) {
        $statusMessage = $Message
        $isBusy = [bool] $Busy
        $updateStatus = {
            $sync.WPFStatusText.Text = $statusMessage
            $sync.WPFProgressBar.IsIndeterminate = $isBusy
        }
        if ($sync.WPFStatusText.Dispatcher.CheckAccess()) {
            & $updateStatus
        }
        else {
            $sync.WPFStatusText.Dispatcher.Invoke([System.Action]$updateStatus)
        }
    }
}
