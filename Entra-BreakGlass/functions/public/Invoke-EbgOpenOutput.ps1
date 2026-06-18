function Invoke-EbgOpenOutputFolder {
    [CmdletBinding()]
    param()

    if ($sync.State.OutputFolder -and (Test-Path -LiteralPath $sync.State.OutputFolder)) {
        Start-Process $sync.State.OutputFolder
    }
    else {
        [System.Windows.MessageBox]::Show('Outputmappen findes ikke endnu.', $sync.App.Name, 'OK', 'Information') | Out-Null
    }
}

function Invoke-EbgOpenHandoff {
    [CmdletBinding()]
    param()

    if ($sync.State.HandoffPath -and (Test-Path -LiteralPath $sync.State.HandoffPath)) {
        Start-Process $sync.State.HandoffPath
    }
    else {
        [System.Windows.MessageBox]::Show('Handoff-dokumentet er ikke genereret endnu.', $sync.App.Name, 'OK', 'Information') | Out-Null
    }
}