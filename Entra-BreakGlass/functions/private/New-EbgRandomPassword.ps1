function New-EbgRandomPassword {
    [CmdletBinding()]
    param([int] $Length = 28)

    if ($Length -lt 24) { $Length = 24 }
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $digits = '23456789'
    $symbols = '!#$%&*+-=?@_'
    $all = ($upper + $lower + $digits + $symbols).ToCharArray()
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    function Get-RandomChar([char[]] $Chars) {
        $bytes = [byte[]]::new(4)
        $rng.GetBytes($bytes)
        return $Chars[[BitConverter]::ToUInt32($bytes, 0) % $Chars.Count]
    }
    $chars = @(
        (Get-RandomChar $upper.ToCharArray()),
        (Get-RandomChar $lower.ToCharArray()),
        (Get-RandomChar $digits.ToCharArray()),
        (Get-RandomChar $symbols.ToCharArray())
    )
    while ($chars.Count -lt $Length) { $chars += Get-RandomChar $all }
    $shuffled = $chars | Sort-Object { Get-Random }
    return -join $shuffled
}