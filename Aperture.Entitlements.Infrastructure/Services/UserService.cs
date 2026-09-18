using System.Security.Cryptography;
using System.Text;
using Aperture.Entitlements.Domain;
using Aperture.Entitlements.Infrastructure.Caching;
using Aperture.Entitlements.Infrastructure.Persistence;
using Aperture.Entitlements.Contracts;
using Microsoft.EntityFrameworkCore;

namespace Aperture.Entitlements.Infrastructure.Services;

public interface IUserService
{
    Task<ResolveUserResponse> ResolveAsync(ResolveUserRequest request, CancellationToken ct);
    Task<UserContextResponse?> GetContextAsync(Guid userId, CancellationToken ct);
    Task<UserSummaryResponse?> FindByEmailAsync(string email, CancellationToken ct);
    Task<UserSummaryResponse?> FindByIdAsync(Guid userId, CancellationToken ct);
    Task<IReadOnlyCollection<UserSummaryResponse>> FindByIdsAsync(
        IReadOnlyCollection<Guid> userIds,
        CancellationToken ct);
    Task<IReadOnlyCollection<Guid>> SearchIdsAsync(string text, CancellationToken ct);
    Task<UserSummaryResponse> AddAsync(AddUserRequest request, CancellationToken ct);
    Task<UserSummaryResponse?> UpdateAsync(UpdateUserRequest request, CancellationToken ct);
}

public sealed class UserService(
    EntitlementsDbContext db,
    IUserContextCache cache,
    TimeProvider timeProvider) : IUserService
{
    public async Task<ResolveUserResponse> ResolveAsync(ResolveUserRequest request, CancellationToken ct)
    {
        var email = request.Email.Trim().ToLowerInvariant();
        var user = await db.Users.SingleOrDefaultAsync(x => x.Email == email, ct);
        var created = user is null;

        if (user is null)
        {
            user = User.Create(request.FirstName, request.LastName, email, request.Status);
            db.Users.Add(user);
        }
        else
        {
            var changed = user.FirstName != request.FirstName.Trim() ||
                          user.LastName != request.LastName.Trim() ||
                          user.Status != request.Status;
            user.Update(request.FirstName, request.LastName, email, request.Status);
            if (changed)
            {
                user.IncrementContextVersion();
                db.OutboxMessages.Add(EntitlementOutboxMessage.Revised(
                    user.UserId,
                    user.ContextVersion,
                    timeProvider.GetUtcNow()));
            }
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException) when (created)
        {
            db.ChangeTracker.Clear();
            user = await db.Users.SingleOrDefaultAsync(x => x.Email == email, ct);
            if (user is null) throw;
            created = false;
        }

        if (!created) await cache.RemoveAsync(user.UserId, ct);
        return new ResolveUserResponse(user.UserId, created);
    }

    public async Task<UserSummaryResponse?> FindByEmailAsync(string email, CancellationToken ct)
    {
        var normalized = email.Trim().ToLowerInvariant();
        var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(x => x.Email == normalized, ct);
        return user is null ? null : Map(user);
    }

    public async Task<UserSummaryResponse?> FindByIdAsync(Guid userId, CancellationToken ct)
    {
        var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(x => x.UserId == userId, ct);
        return user is null ? null : Map(user);
    }

    public async Task<IReadOnlyCollection<UserSummaryResponse>> FindByIdsAsync(
        IReadOnlyCollection<Guid> userIds,
        CancellationToken ct)
    {
        var ids = userIds.Where(x => x != Guid.Empty).Distinct().ToArray();
        if (ids.Length == 0) return [];
        var users = await db.Users.AsNoTracking()
            .Where(x => ids.Contains(x.UserId))
            .OrderBy(x => x.Email)
            .ToArrayAsync(ct);
        return users.Select(Map).ToArray();
    }

    public async Task<IReadOnlyCollection<Guid>> SearchIdsAsync(
        string text,
        CancellationToken ct)
    {
        var value = text.Trim().ToLowerInvariant();
        if (value.Length < 2) throw new ArgumentException("Search text must contain at least two characters.");
        return await db.Users.AsNoTracking()
            .Where(x => x.Email.ToLower().Contains(value) ||
                        x.FirstName.ToLower().Contains(value) ||
                        x.LastName.ToLower().Contains(value))
            .OrderBy(x => x.Email)
            .Select(x => x.UserId)
            .Take(100)
            .ToArrayAsync(ct);
    }

    public async Task<UserSummaryResponse> AddAsync(AddUserRequest request, CancellationToken ct)
    {
        var user = User.Create(request.FirstName, request.LastName, request.Email, request.Status);
        db.Users.Add(user);
        await db.SaveChangesAsync(ct);
        return Map(user);
    }

    public async Task<UserSummaryResponse?> UpdateAsync(
        UpdateUserRequest request,
        CancellationToken ct)
    {
        if (request.UserId == Guid.Empty) throw new ArgumentException("UserId is required.");
        var user = await db.Users.SingleOrDefaultAsync(x => x.UserId == request.UserId, ct);
        if (user is null) return null;

        user.Update(request.FirstName, request.LastName, request.Email, request.Status);
        user.IncrementContextVersion();
        db.OutboxMessages.Add(EntitlementOutboxMessage.Revised(
            user.UserId,
            user.ContextVersion,
            timeProvider.GetUtcNow()));
        await db.SaveChangesAsync(ct);
        await cache.RemoveAsync(user.UserId, ct);
        return Map(user);
    }

    public async Task<UserContextResponse?> GetContextAsync(Guid userId, CancellationToken ct)
    {
        var cached = await cache.GetAsync(userId, ct);
        if (cached is not null) return cached;

        var today = DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime);
        var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(x => x.UserId == userId, ct);
        if (user is null) return null;

        var roles = await db.RoleAssignments.AsNoTracking()
            .Where(x => x.UserId == userId &&
                        x.Role.Status == "active" &&
                        x.RevokedAt == null &&
                        x.EffectiveFrom <= today &&
                        (x.EffectiveTo == null || today < x.EffectiveTo))
            .Select(x => x.Role.RoleKey)
            .Distinct()
            .OrderBy(x => x)
            .ToArrayAsync(ct);

        var etagPayload = $"{user.UserId:N}:{user.ContextVersion}";
        var etag = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(etagPayload)))
            .ToLowerInvariant();
        var result = new UserContextResponse(
            user.UserId,
            user.FirstName,
            user.LastName,
            user.Email,
            user.Status,
            roles,
            user.ContextVersion,
            $"\"{etag}\"");
        await cache.SetAsync(result, ct);
        return result;
    }

    private static UserSummaryResponse Map(User user) => new(
        user.UserId,
        user.FirstName,
        user.LastName,
        user.Email,
        user.Status);
}
