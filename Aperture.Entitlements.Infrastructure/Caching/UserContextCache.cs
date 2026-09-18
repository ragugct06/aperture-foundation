using System.Text.Json;
using Aperture.Entitlements.Contracts;
using Microsoft.Extensions.Caching.Distributed;

namespace Aperture.Entitlements.Infrastructure.Caching;

public interface IUserContextCache
{
    Task<UserContextResponse?> GetAsync(Guid userId, CancellationToken ct);
    Task SetAsync(UserContextResponse context, CancellationToken ct);
    Task RemoveAsync(Guid userId, CancellationToken ct);
}

public sealed class UserContextCache(IDistributedCache cache) : IUserContextCache
{
    private static string Key(Guid id) => $"ent:user:{id:N}";

    public async Task<UserContextResponse?> GetAsync(Guid userId, CancellationToken ct)
    {
        var payload = await cache.GetStringAsync(Key(userId), ct);
        return payload is null ? null : JsonSerializer.Deserialize<UserContextResponse>(payload);
    }

    public Task SetAsync(UserContextResponse context, CancellationToken ct) =>
        cache.SetStringAsync(
            Key(context.UserId),
            JsonSerializer.Serialize(context),
            new DistributedCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(15),
                SlidingExpiration = TimeSpan.FromMinutes(5)
            },
            ct);

    public Task RemoveAsync(Guid userId, CancellationToken ct) => cache.RemoveAsync(Key(userId), ct);
}
