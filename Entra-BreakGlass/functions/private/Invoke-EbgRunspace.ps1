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
    $sync.UI.ProcessStarted = Get-Date
    Invoke-EbgUIThread -ScriptBlock {
        if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $true }
        Update-EbgUIState | Out-Null
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
                Invoke-EbgUIThread -ScriptBlock {
                    param([string] $message)
                    if ($sync.WPFStatusText) { $sync.WPFStatusText.Text = $message }
                    [System.Windows.MessageBox]::Show($message, $sync.App.Name, 'OK', 'Error') | Out-Null
                } -ArgumentList @($friendly)
            }
        }
        finally {
            $sync.UI.ProcessRunning = $false
            $sync.UI.CurrentPowerShell = $null
            $sync.UI.CurrentAsync = $null
            if ($sync.Form) {
                Invoke-EbgUIThread -ScriptBlock {
                    if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $false }
                    Update-EbgUIState | Out-Null
                }
            }
        }
    }).AddArgument($ScriptBlock).AddArgument($ArgumentList) | Out-Null
    $async = $ps.BeginInvoke()
    $sync.UI.CurrentPowerShell = $ps
    $sync.UI.CurrentAsync = $async
    $watchPowerShell = $ps
    $watchAsync = $async
    [System.Threading.ThreadPool]::QueueUserWorkItem([System.Threading.WaitCallback]{
        param($state)

        Start-Sleep -Seconds 60
        try {
            if ($state.Async -and -not $state.Async.IsCompleted -and $sync.UI.ProcessRunning) {
                $started = $sync.UI.ProcessStarted
                $elapsed = if ($started) { [int]((Get-Date) - [datetime]$started).TotalSeconds } else { 60 }
                Write-EbgLog -Level WARN -Message "Baggrundsopgaven kører stadig efter $elapsed sekunder. Hvis UI ikke går videre, brug Stop/Luk og prøv igen."
                Write-EbgStatus -Busy -Message "Baggrundsopgaven kører stadig efter $elapsed sekunder..."
            }
        }
        catch {
            # Watchdog must never affect the worker operation.
        }
    }, [pscustomobject]@{ PowerShell = $watchPowerShell; Async = $watchAsync }) | Out-Null
    [void]$async
}
