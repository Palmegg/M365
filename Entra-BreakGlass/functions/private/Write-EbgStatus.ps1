function Write-EbgStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [switch] $Busy
    )

    Write-EbgLog -Message $Message
    if ($sync.WPFStatusText) {
        $statusMessage = $Message
        $isBusy = [bool] $Busy
        $updateStatus = {
            $sync.WPFStatusText.Text = $statusMessage
            $sync.WPFProgressBar.IsIndeterminate = $isBusy
        }
        if ($sync.WPFStatusText.Dispatcher.CheckAccess()) {
            & $updateStatus | Out-Null
        }
        else {
            [void]$sync.WPFStatusText.Dispatcher.Invoke([System.Action]$updateStatus)
        }
    }
}