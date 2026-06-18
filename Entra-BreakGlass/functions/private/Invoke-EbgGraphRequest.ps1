function Invoke-EbgGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PATCH','DELETE')][string] $Method,
        [Parameter(Mandatory)][string] $Uri,
        [AllowNull()] $Body = $null,
        [switch] $SuppressNotFoundLog
    )

    if ($sync.App.Mock) {
        throw 'Mock mode should not call Microsoft Graph.'
    }
    Ensure-EbgGraphContext
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
        $message = [string]$_
        $isNotFound = $message -match '404|Request_ResourceNotFound|Resource .* does not exist'
        if (-not ($SuppressNotFoundLog -and $isNotFound)) {
            Write-EbgLog -Level ERROR -Message (ConvertTo-EbgRedactedError -ErrorRecord $_)
        }
        throw
    }
}
