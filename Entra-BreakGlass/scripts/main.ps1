$maxThreads = 1
$initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$initialSessionState.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'sync', $sync, $null))
$initialSessionState.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DebugPreference', $DebugPreference, $null))

Get-ChildItem function:\ | Where-Object { $_.Name -like '*-Ebg*' -or $_.Name -like '*-BreakGlass*' } | ForEach-Object {
    $definition = Get-Content function:\$($_.Name)
    $initialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $_.Name, $definition))
}

$sync.Runspace = [runspacefactory]::CreateRunspacePool(1, $maxThreads, $initialSessionState, $Host)
$sync.Runspace.ApartmentState = 'STA'
$sync.Runspace.ThreadOptions = 'ReuseThread'
$sync.Runspace.Open()

$inputXML = $inputXML -replace 'mc:Ignorable="d"', '' -replace 'x:Name', 'Name'
[xml]$xaml = $inputXML
$reader = New-Object System.Xml.XmlNodeReader $xaml
$sync.Form = [Windows.Markup.XamlReader]::Load($reader)

$xaml.SelectNodes("//*[@Name]") | ForEach-Object {
    $sync[$_.Name] = $sync.Form.FindName($_.Name)
}

Initialize-EbgWPFUI

$sync.Keys | ForEach-Object {
    $control = $sync[$_]
    if ($control -and $control.GetType().Name -eq 'Button' -and $_ -like 'WPF*') {
        $control.Add_Click({
            param($sender, $eventArgs)
            try {
                Invoke-EbgWPFButton -Name $sender.Name | Out-Null
            }
            catch {
                $message = ConvertTo-EbgRedactedError -ErrorRecord $_
                Write-EbgLog -Level ERROR -Message $message
                [System.Windows.MessageBox]::Show($message, $sync.App.Name, 'OK', 'Error') | Out-Null
            }
        })
    }
}

foreach ($box in @('WPFDisplayName1','WPFUserPrefix1','WPFDisplayName2','WPFUserPrefix2')) {
    if ($sync[$box]) {
        $sync[$box].Add_TextChanged({ Update-EbgUIState })
    }
}
foreach ($box in @('WPFPhase2UserPrefix1','WPFPhase2UserPrefix2')) {
    if ($sync[$box]) {
        $sync[$box].Add_TextChanged({ Update-EbgUIState })
    }
}

$sync.WPFWelcomeRiskAccepted.Add_Checked({ Update-EbgUIState | Out-Null })
$sync.WPFWelcomeRiskAccepted.Add_Unchecked({ Update-EbgUIState | Out-Null })
if ($sync.WPFRegularSSPROnly) {
    $sync.WPFRegularSSPROnly.Add_Checked({ Update-EbgUIState | Out-Null })
    $sync.WPFRegularSSPROnly.Add_Unchecked({ Update-EbgUIState | Out-Null })
}
foreach ($box in @('WPFRegularSSPRAdmin1','WPFRegularSSPRAdmin2')) {
    if ($sync[$box]) {
        $sync[$box].Add_SelectionChanged({ Update-EbgUIState | Out-Null })
    }
}
$updateUIStateScript = ${function:Update-EbgUIState}
foreach ($box in @('WPFAAGUIDSourceAdmin1','WPFAAGUIDSourceAdmin2')) {
    if ($sync[$box]) {
        $sync[$box].Add_SelectionChanged({
            if ([bool]$sync.UI.SuppressAAGUIDSourceChange) { return }
            & $updateUIStateScript | Out-Null
        }.GetNewClosure())
    }
}
if ($sync.WPFStartPhase1) {
    $sync.WPFStartPhase1.Add_Checked({
        $sync.State.StartMode = 'Phase1'
        Update-EbgUIState | Out-Null
    })
}
if ($sync.WPFResumePhase2) {
    $sync.WPFResumePhase2.Add_Checked({
        $sync.State.StartMode = 'Phase2'
        Update-EbgUIState | Out-Null
    })
}
if ($sync.WPFLanguageSelector) {
    $sync.WPFLanguageSelector.Add_SelectionChanged({
        $selected = $sync.WPFLanguageSelector.SelectedItem
        $language = if ($selected -and $selected.Tag) { [string]$selected.Tag } else { 'da-DK' }
        Set-EbgLanguage -Language $language | Out-Null
        Update-EbgUIState | Out-Null
    })
}

$sync.Form.Add_Closing({
    param($sender, $eventArgs)

    if ([bool]$sync.UI.CloseInProgress) {
        return
    }

    if ([bool]$sync.UI.ProcessRunning) {
        if (-not [bool]$sync.UI.AllowForcedClose) {
            $answer = [System.Windows.MessageBox]::Show(
                'Der kører en baggrundsopgave. Vil du stoppe opgaven og lukke configuratoren?',
                $sync.App.Name,
                'YesNo',
                'Warning'
            )
            if ($answer -ne 'Yes') {
                $eventArgs.Cancel = $true
                return
            }
        }

        $eventArgs.Cancel = $true
        $sync.UI.AllowForcedClose = $true
        $sync.UI.CloseInProgress = $true
        $sync.UI.StopRequested = $true
        Write-EbgStatus -Busy -Message 'Stopper baggrundsopgave og lukker configuratoren...'

        $targetPowerShell = $sync.UI.CurrentPowerShell
        $targetRunspace = $sync.Runspace
        [System.Threading.ThreadPool]::QueueUserWorkItem([System.Threading.WaitCallback]{
            param($state)

            try {
                if ($state.PowerShell) {
                    try { $state.PowerShell.Stop() } catch {}
                    try { $state.PowerShell.Dispose() } catch {}
                }
                if ($state.Runspace) {
                    try { $state.Runspace.Dispose() } catch {}
                }
            }
            finally {
                $sync.UI.ProcessRunning = $false
                $sync.UI.CurrentPowerShell = $null
                $sync.UI.CurrentAsync = $null
                if ($sync.Form) {
                    [void]$sync.Form.Dispatcher.BeginInvoke([System.Action]{
                        $sync.UI.CloseInProgress = $false
                        $sync.Form.Close()
                    })
                }
            }
        }, [pscustomobject]@{ PowerShell = $targetPowerShell; Runspace = $targetRunspace }) | Out-Null
        return
    }

    if ($sync.UI.CurrentPowerShell) {
        try { $sync.UI.CurrentPowerShell.Dispose() } catch {}
    }
    if ($sync.Runspace) {
        try { $sync.Runspace.Dispose() } catch {}
    }
})

[void]$sync.Form.ShowDialog()
