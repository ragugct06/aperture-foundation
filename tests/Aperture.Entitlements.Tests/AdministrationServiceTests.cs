using Aperture.Entitlements.Contracts;
using Aperture.Entitlements.Domain;
using Aperture.Entitlements.Infrastructure.Persistence;
using Aperture.Entitlements.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;

namespace Aperture.Entitlements.Tests;

public sealed class AdministrationServiceTests
{
    [Fact]
    public async Task Update_with_key_renames_the_role_and_keeps_its_id()
    {
        await using var db = CreateDatabase();
        var role = Role.Create("Specialist", "Handles benefits", DateTimeOffset.UtcNow);
        db.Roles.Add(role);
        await db.SaveChangesAsync();
        var service = CreateService(db);

        var updated = await service.UpdateRoleAsync(role.RoleId, new UpdateRoleRequest
        {
            Key = "Lead_Specialist",
            Description = "Handles benefits",
            Status = "active"
        }, CancellationToken.None);

        Assert.Equal(role.RoleId, updated!.RoleId);
        Assert.Equal("Lead_Specialist", updated.Key);
        Assert.Equal("Lead_Specialist", (await db.Roles.SingleAsync()).RoleKey);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task Update_without_a_key_keeps_the_existing_key(string? key)
    {
        await using var db = CreateDatabase();
        var role = Role.Create("Specialist", "Handles benefits", DateTimeOffset.UtcNow);
        db.Roles.Add(role);
        await db.SaveChangesAsync();
        var service = CreateService(db);

        var updated = await service.UpdateRoleAsync(role.RoleId, new UpdateRoleRequest
        {
            Key = key,
            Description = "New description",
            Status = "active"
        }, CancellationToken.None);

        Assert.Equal("Specialist", updated!.Key);
        Assert.Equal("New description", updated.Description);
    }

    [Fact]
    public async Task Renaming_a_role_bumps_the_context_version_of_assigned_users()
    {
        await using var db = CreateDatabase();
        var user = User.Create("Test", "User", "test@example.test", "active");
        var role = Role.Create("Specialist", "Handles benefits", DateTimeOffset.UtcNow);
        db.Users.Add(user);
        db.Roles.Add(role);
        db.RoleAssignments.Add(RoleAssignment.Create(
            user.UserId, role.RoleId, DateOnly.FromDateTime(DateTime.UtcNow.AddDays(-1)),
            null, "test", DateTimeOffset.UtcNow));
        await db.SaveChangesAsync();
        var before = user.ContextVersion;
        var service = CreateService(db);

        await service.UpdateRoleAsync(role.RoleId, new UpdateRoleRequest
        {
            Key = "Lead_Specialist",
            Description = "Handles benefits",
            Status = "active"
        }, CancellationToken.None);

        Assert.Equal(before + 1, (await db.Users.SingleAsync()).ContextVersion);
        Assert.Single(await db.RoleAssignments.ToListAsync());
    }

    [Fact]
    public async Task Update_of_unknown_role_returns_null()
    {
        await using var db = CreateDatabase();
        var service = CreateService(db);

        var result = await service.UpdateRoleAsync(Guid.NewGuid(), new UpdateRoleRequest
        {
            Key = "Anything",
            Description = "x",
            Status = "active"
        }, CancellationToken.None);

        Assert.Null(result);
    }

    private static EntitlementAdministrationService CreateService(EntitlementsDbContext db) =>
        new(db, new TestUserContextCache(), TimeProvider.System);

    private static EntitlementsDbContext CreateDatabase() =>
        new(new DbContextOptionsBuilder<EntitlementsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
}
