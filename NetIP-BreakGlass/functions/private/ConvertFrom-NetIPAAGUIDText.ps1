function ConvertFrom-NetIPAAGUIDText {
    [CmdletBinding()]
    param([AllowNull()][string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $matches = [regex]::Matches($Text, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    $values = @($matches | ForEach-Object { $_.Value.ToLowerInvariant() } | Select-Object -Unique)
    return $values
}
