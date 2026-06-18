$maxThreads = 1
$initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$initialSessionState.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'sync', $sync, $null))
$initialSessionState.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DebugPreference', $DebugPreference, $null))

Get-ChildItem function:\ | Where-Object { $_.Name -like '*-Ebg*' -or $_.Name -like '*-BreakGlass*' } | ForEach-Object {
    $definition = Get-Content function:\$($_.Name)
    $initialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $_.Name, $definition))
}

$sync.Runspace = [runspacefactory]::CreateRunspacePool(1, $maxThreads, $initialSessionState, $Host)
$sync.Runspace.ApartmentState = 'MTA'
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

$sync.WPFWelcomeRiskAccepted.Add_Checked({ Update-EbgUIState | Out-Null })
$sync.WPFWelcomeRiskAccepted.Add_Unchecked({ Update-EbgUIState | Out-Null })
if ($sync.WPFLanguageSelector) {
    $sync.WPFLanguageSelector.Add_SelectionChanged({
        $selected = $sync.WPFLanguageSelector.SelectedItem
        $language = if ($selected -and $selected.Tag) { [string]$selected.Tag } else { 'da-DK' }
        Set-EbgLanguage -Language $language | Out-Null
        Update-EbgUIState | Out-Null
    })
}

$sync.Form.Add_Closing({
    if ($sync.Runspace) {
        $sync.Runspace.Close()
        $sync.Runspace.Dispose()
    }
})

[void]$sync.Form.ShowDialog()
