function Invoke-EbgRunspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock] $ScriptBlock,
        [object[]] $ArgumentList = @()
    )

    if ($sync.UI.ProcessRunning) {
        [System.Windows.MessageBox]::Show('Der kører allerede en opgave. Vent til den er færdig.', $sync.App.Name, 'OK', 'Information') | Out-Null
        return
    }
    $sync.UI.ProcessRunning = $true
    $sync.UI.StopRequested = $false
    if ($sync.WPFProgressBar) {
        [void]$sync.WPFProgressBar.Dispatcher.Invoke([System.Action]{
            $sync.WPFProgressBar.IsIndeterminate = $true
            Update-EbgUIState | Out-Null
        })
    }
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $sync.Runspace
    [void]$ps.AddScript({
        param($innerScript, $innerArgs)
        try {
            & $innerScript @innerArgs
        }
        catch {
            $friendly = 'Der opstod en fejl. Se logfilen for tekniske detaljer.'
            Write-EbgLog -Level ERROR -Message (ConvertTo-EbgRedactedError -ErrorRecord $_)
            $sync.State.Errors += $friendly
            if ($sync.Form) {
                [void]$sync.Form.Dispatcher.Invoke([System.Action]{
                    $sync.WPFStatusText.Text = $friendly
                    [System.Windows.MessageBox]::Show($friendly, $sync.App.Name, 'OK', 'Error') | Out-Null
                })
            }
        }
        finally {
            $sync.UI.ProcessRunning = $false
            $sync.UI.CurrentPowerShell = $null
            $sync.UI.CurrentAsync = $null
            if ($sync.Form) {
                [void]$sync.Form.Dispatcher.Invoke([System.Action]{
                    $sync.WPFProgressBar.IsIndeterminate = $false
                    Update-EbgUIState | Out-Null
                })
            }
        }
    }).AddArgument($ScriptBlock).AddArgument($ArgumentList) | Out-Null
    $async = $ps.BeginInvoke()
    $sync.UI.CurrentPowerShell = $ps
    $sync.UI.CurrentAsync = $async
    [void]$async
}
