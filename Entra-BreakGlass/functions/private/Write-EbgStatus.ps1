function Write-EbgStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [switch] $Busy
    )

    Write-EbgLog -Message $Message
    if ($sync.WPFStatusText -and $sync.Form -and $sync.Form.Dispatcher) {
        $statusMessage = $Message
        $isBusy = [bool] $Busy
        $updateStatus = {
            try {
                $sync.WPFStatusText.Text = $statusMessage
                $sync.WPFProgressBar.IsIndeterminate = $isBusy
            }
            catch {
                # UI status updates must never break the worker operation.
            }
        }
        [void]$sync.Form.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action]$updateStatus.GetNewClosure())
    }
}
