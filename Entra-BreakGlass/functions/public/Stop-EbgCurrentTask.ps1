function Stop-EbgCurrentTask {
    [CmdletBinding()]
    param()

    $ps = $sync.UI.CurrentPowerShell
    if (-not $sync.UI.ProcessRunning -or -not $ps) {
        Write-EbgStatus -Message 'Der kører ingen baggrundsopgave at stoppe.'
        return
    }

    $sync.UI.StopRequested = $true
    Write-EbgStatus -Busy -Message 'Stopper baggrundsopgave...'
    if ($sync.WPFStopDiscovery) { $sync.WPFStopDiscovery.IsEnabled = $false }

    $targetPowerShell = $ps
    [System.Threading.ThreadPool]::QueueUserWorkItem([System.Threading.WaitCallback]{
        param($state)

        try {
            $state.Stop()
            Write-EbgStatus -Message 'Baggrundsopgave stoppet.'
        }
        catch {
            Write-EbgLog -Level WARN -Message "Kunne ikke stoppe baggrundsopgaven rent: $($_.Exception.Message)"
            Write-EbgStatus -Message 'Stop blev sendt, men opgaven svarer ikke endnu.'
        }
        finally {
            $sync.UI.ProcessRunning = $false
            $sync.UI.CurrentPowerShell = $null
            $sync.UI.CurrentAsync = $null
            if ($sync.Form) {
                [void]$sync.Form.Dispatcher.Invoke([System.Action]{
                    if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $false }
                    Update-EbgUIState | Out-Null
                })
            }
        }
    }, $targetPowerShell) | Out-Null
}
