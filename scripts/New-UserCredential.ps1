<# Generates SQL for an existing user; does not connect to or modify a database.
   Run the generated SQL through psql against the Entitlements database.
   Passwords are prompted securely and are never included in the SQL output.
#>
param(
    [Parameter(Mandatory=$true)][Guid]$UserId,
    [Parameter(Mandatory=$true)][ValidateLength(1,320)][string]$Username
)
$ErrorActionPreference = 'Stop'
if ($UserId -eq [Guid]::Empty -or [string]::IsNullOrWhiteSpace($Username)) { throw 'UserId and username are required.' }
$secret = Read-Host 'Password (15 to 1024 characters)' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
try {
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ($password.Length -lt 15 -or $password.Length -gt 1024) { throw 'Password must contain 15 to 1024 characters.' }
    $salt = New-Object byte[] 16
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($salt) } finally { $rng.Dispose() }
    $derive = [Security.Cryptography.Rfc2898DeriveBytes]::new($password, $salt, 600000, [Security.Cryptography.HashAlgorithmName]::SHA256)
    try { $hash = $derive.GetBytes(32) } finally { $derive.Dispose() }
    $saltHex = [BitConverter]::ToString($salt).Replace('-', '')
    $hashHex = [BitConverter]::ToString($hash).Replace('-', '')
    $name = $Username.Trim().ToLowerInvariant().Replace("'", "''")
    @"
SET standard_conforming_strings = on;
INSERT INTO entitlement.user_credential (user_id, username, password_salt, password_hash)
VALUES ('$UserId', '$name', decode('$saltHex', 'hex'), decode('$hashHex', 'hex'));
"@
} finally {
    $password = $null
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    $secret.Dispose()
}
