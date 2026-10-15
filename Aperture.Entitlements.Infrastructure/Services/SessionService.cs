using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Options;

namespace Aperture.Entitlements.Infrastructure.Services;

/// <summary>
/// APP-1417: server-side login sessions owned by foundation.
///
/// A successful login creates a session record in the distributed cache (Redis in every deployed
/// environment, in-process memory for local development and tests) under an opaque random id.
/// Callers hold only that id, so no service needs to encrypt or share cookie keys, and any number
/// of foundation or consumer replicas can resolve the same session without sticky routing.
/// </summary>
public interface ISessionService
{
    Task<UserSession> CreateAsync(LoginAuthenticationResult user, CancellationToken ct);

    /// <summary>Returns the live session for <paramref name="sessionId"/>, or null when unknown, expired or malformed.</summary>
    Task<UserSession?> GetAsync(string? sessionId, CancellationToken ct);

    Task RevokeAsync(string? sessionId, CancellationToken ct);
}

public sealed class LoginSessionOptions
{
    public const string SectionName = "Session";

    /// <summary>Sliding lifetime: a session ends after this long with no request that resolved it.</summary>
    public TimeSpan Lifetime { get; set; } = TimeSpan.FromHours(8);

    /// <summary>Cookie that carries the session id to browsers. Header X-Aperture-Session is accepted too.</summary>
    public string CookieName { get; set; } = "Aperture.Session";
}

public sealed record UserSession(
    string SessionId,
    Guid UserId,
    string FirstName,
    string LastName,
    string Email,
    IReadOnlyCollection<string> Roles,
    DateTimeOffset CreatedAt,
    DateTimeOffset ExpiresAt);

public sealed class SessionService(
    IDistributedCache cache,
    IOptions<LoginSessionOptions> options,
    TimeProvider timeProvider) : ISessionService
{
    public const string HeaderName = "X-Aperture-Session";

    // 256 bits of randomness, base64url: 43 characters from [A-Za-z0-9-_].
    private const int SessionIdBytes = 32;
    private const int SessionIdLength = 43;

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<UserSession> CreateAsync(LoginAuthenticationResult user, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(user);
        var now = timeProvider.GetUtcNow();
        var session = new UserSession(
            NewSessionId(),
            user.UserId,
            user.FirstName,
            user.LastName,
            user.Email,
            user.Roles.ToArray(),
            now,
            now.Add(options.Value.Lifetime));

        await cache.SetStringAsync(
            Key(session.SessionId),
            JsonSerializer.Serialize(session, JsonOptions),
            new DistributedCacheEntryOptions { SlidingExpiration = options.Value.Lifetime },
            ct);
        return session;
    }

    public async Task<UserSession?> GetAsync(string? sessionId, CancellationToken ct)
    {
        if (!IsWellFormed(sessionId)) return null;

        // Reading refreshes the sliding expiration in both the Redis and the memory implementation.
        var payload = await cache.GetStringAsync(Key(sessionId), ct);
        if (payload is null) return null;

        var stored = JsonSerializer.Deserialize<UserSession>(payload, JsonOptions);
        if (stored is null) return null;

        // ExpiresAt is informational for callers (the cache owns the real expiry): keep it current.
        return stored with { ExpiresAt = timeProvider.GetUtcNow().Add(options.Value.Lifetime) };
    }

    public Task RevokeAsync(string? sessionId, CancellationToken ct) =>
        IsWellFormed(sessionId) ? cache.RemoveAsync(Key(sessionId), ct) : Task.CompletedTask;

    private static string Key(string sessionId) => $"ent:session:{sessionId}";

    private static string NewSessionId() =>
        Convert.ToBase64String(RandomNumberGenerator.GetBytes(SessionIdBytes))
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');

    // Rejects anything that is not one of our own ids before it reaches the cache, so arbitrary
    // input can never probe or address other key families.
    private static bool IsWellFormed([System.Diagnostics.CodeAnalysis.NotNullWhen(true)] string? sessionId) =>
        sessionId is { Length: SessionIdLength }
        && sessionId.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_');
}
