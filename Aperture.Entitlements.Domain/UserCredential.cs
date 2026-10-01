namespace Aperture.Entitlements.Domain;

public sealed class UserCredential
{
    public Guid UserId { get; set; }
    public string Username { get; set; } = "";
    public byte[] PasswordSalt { get; set; } = [];
    public byte[] PasswordHash { get; set; } = [];
}
