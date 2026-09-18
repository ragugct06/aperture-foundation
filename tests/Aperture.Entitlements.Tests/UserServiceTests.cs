using Aperture.Entitlements.Infrastructure.Caching;
using Aperture.Entitlements.Infrastructure.Persistence;
using Aperture.Entitlements.Infrastructure.Services;
using Aperture.Entitlements.Contracts;
using Microsoft.EntityFrameworkCore;

namespace Aperture.Entitlements.Tests;

public sealed class UserServiceTests
{
    [Fact]
    public async Task Resolve_is_idempotent_by_normalized_email()
    {
        await using var db = CreateDatabase();
        var service = new UserService(
            db,
            new TestUserContextCache(),
            new FixedTimeProvider(new DateTimeOffset(2026, 9, 18, 12, 0, 0, TimeSpan.Zero)));
        var request = new ResolveUserRequest
        {
            FirstName = "Test",
            LastName = "User",
            Email = "User@Example.Test",
            Status = "active"
        };

        var first = await service.ResolveAsync(request, CancellationToken.None);
        var second = await service.ResolveAsync(request, CancellationToken.None);

        Assert.True(first.Created);
        Assert.False(second.Created);
        Assert.Equal(first.UserId, second.UserId);
        Assert.Equal(1, await db.Users.CountAsync());
    }

    [Fact]
    public async Task New_user_has_active_context_with_no_roles()
    {
        await using var db = CreateDatabase();
        var service = new UserService(
            db,
            new TestUserContextCache(),
            new FixedTimeProvider(new DateTimeOffset(2026, 9, 18, 12, 0, 0, TimeSpan.Zero)));
        var resolved = await service.ResolveAsync(new ResolveUserRequest
        {
            FirstName = "Test",
            LastName = "User",
            Email = "user@example.test",
            Status = "active"
        }, CancellationToken.None);

        var context = await service.GetContextAsync(resolved.UserId, CancellationToken.None);

        Assert.NotNull(context);
        Assert.Equal("active", context.Status);
        Assert.Empty(context.Roles);
        Assert.StartsWith("\"", context.ETag);
    }

    [Fact]
    public async Task Add_find_and_update_use_the_same_user_record()
    {
        await using var db = CreateDatabase();
        var service = new UserService(
            db,
            new TestUserContextCache(),
            new FixedTimeProvider(new DateTimeOffset(2026, 9, 18, 12, 0, 0, TimeSpan.Zero)));
        var added = await service.AddAsync(new AddUserRequest
        {
            FirstName = "First",
            LastName = "Name",
            Email = "first@example.test",
            Status = "active"
        }, CancellationToken.None);

        var byEmail = await service.FindByEmailAsync("FIRST@example.test", CancellationToken.None);
        var updated = await service.UpdateAsync(new UpdateUserRequest
        {
            UserId = added.UserId,
            FirstName = "Updated",
            LastName = "Name",
            Email = "updated@example.test",
            Status = "suspended"
        }, CancellationToken.None);

        Assert.Equal(added.UserId, byEmail?.UserId);
        Assert.Equal("Updated", updated?.FirstName);
        Assert.Equal("updated@example.test", updated?.Email);
        Assert.Equal("suspended", updated?.Status);
    }

    private static EntitlementsDbContext CreateDatabase()
    {
        var options = new DbContextOptionsBuilder<EntitlementsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        return new EntitlementsDbContext(options);
    }
}

internal sealed class TestUserContextCache : IUserContextCache
{
    private readonly Dictionary<Guid, UserContextResponse> _items = [];

    public Task<UserContextResponse?> GetAsync(Guid userId, CancellationToken ct) =>
        Task.FromResult(_items.GetValueOrDefault(userId));

    public Task SetAsync(UserContextResponse context, CancellationToken ct)
    {
        _items[context.UserId] = context;
        return Task.CompletedTask;
    }

    public Task RemoveAsync(Guid userId, CancellationToken ct)
    {
        _items.Remove(userId);
        return Task.CompletedTask;
    }
}

internal sealed class FixedTimeProvider(DateTimeOffset value) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => value;
}
