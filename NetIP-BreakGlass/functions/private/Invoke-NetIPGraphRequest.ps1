function Invoke-NetIPGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PATCH','DELETE')][string] $Method,
        [Parameter(Mandatory)][string] $Uri,
        [AllowNull()] $Body = $null
    )

    if ($sync.App.Mock) {
        throw 'Mock mode should not call Microsoft Graph.'
    }
    $params = @{
        Method      = $Method
        Uri         = $Uri
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $params.Body = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 30) }
        $params.ContentType = 'application/json'
    }
    try {
        return Invoke-MgGraphRequest @params
    }
    catch {
        Write-NetIPLog -Level ERROR -Message (ConvertTo-NetIPRedactedError -ErrorRecord $_)
        throw
    }
}
