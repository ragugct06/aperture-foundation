using System.Security.Cryptography;
using Aperture.Entitlements.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Aperture.Entitlements.Infrastructure.Services;

public sealed class LoginService(EntitlementsDbContext db, TimeProvider timeProvider)
{
    public const int PasswordIterations = 600_000;
    private static readonly byte[] DummySalt = RandomNumberGenerator.GetBytes(16);

    public async Task<LoginAuthenticationResult?> AuthenticateAsync(
        string username,
        string password,
        CancellationToken ct)
    {
        var normalized = username.Trim().ToLowerInvariant();
        var account = await (
            from credential in db.UserCredentials.AsNoTracking()
            join user in db.Users.AsNoTracking() on credential.UserId equals user.UserId
            where credential.Username == normalized
            select new
            {
                credential.PasswordSalt,
                credential.PasswordHash,
                user.UserId,
                user.FirstName,
                user.LastName,
                user.Email,
                user.Status
            })
            .SingleOrDefaultAsync(ct);

        // Perform the same expensive derivation for unknown and inactive accounts.
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, account?.PasswordSalt ?? DummySalt,
            PasswordIterations, HashAlgorithmName.SHA256, 32);
        var matches = CryptographicOperations.FixedTimeEquals(hash, account?.PasswordHash ?? new byte[32]);
        CryptographicOperations.ZeroMemory(hash);
        if (account is null || !matches || account.Status != "active") return null;

        var today = DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime);
        var roles = await db.RoleAssignments.AsNoTracking()
            .Where(assignment =>
                assignment.UserId == account.UserId &&
                assignment.RevokedAt == null &&
                assignment.EffectiveFrom <= today &&
                (assignment.EffectiveTo == null || assignment.EffectiveTo > today) &&
                assignment.Role.Status == "active")
            .Select(assignment => assignment.Role.RoleKey)
            .Distinct()
            .OrderBy(role => role)
            .ToListAsync(ct);

        return new LoginAuthenticationResult(
            account.UserId,
            account.FirstName,
            account.LastName,
            account.Email,
            roles);
    }
}

public sealed record LoginAuthenticationResult(
    Guid UserId,
    string FirstName,
    string LastName,
    string Email,
    IReadOnlyCollection<string> Roles);
