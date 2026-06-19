function Write-EbgStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [switch] $Busy
    )

    Write-EbgLog -Message $Message
    if ($sync.Form -and $sync.Form.Dispatcher) {
        Invoke-EbgUIThread -ScriptBlock {
            param(
                [string] $statusMessage,
                [bool] $isBusy
            )

            if ($sync.WPFStatusText) {
                $sync.WPFStatusText.Text = $statusMessage
            }
            if ($sync.WPFProgressBar) {
                $sync.WPFProgressBar.IsIndeterminate = $isBusy
            }
        } -ArgumentList @($Message, [bool] $Busy)
    }
}
