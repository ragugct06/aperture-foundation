using Aperture.Entitlements.Domain;
using Aperture.Entitlements.Infrastructure.Caching;
using Aperture.Entitlements.Infrastructure.Persistence;
using Aperture.Entitlements.Contracts;
using Microsoft.EntityFrameworkCore;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Threading;
using System;
using System.Linq;

namespace Aperture.Entitlements.Infrastructure.Services;

public interface IEntitlementAdministrationService
{
    Task<IReadOnlyCollection<RoleResponse>> ListRolesAsync(CancellationToken ct);
    Task<RoleResponse?> GetRoleAsync(Guid id, CancellationToken ct);
    Task<RoleResponse> CreateRoleAsync(CreateRoleRequest request, CancellationToken ct);
    Task<RoleResponse?> UpdateRoleAsync(Guid id, UpdateRoleRequest request, CancellationToken ct);
    Task<bool> RetireRoleAsync(Guid id, CancellationToken ct);
    Task<IReadOnlyCollection<RoleAssignmentResponse>> ListAssignmentsAsync(Guid userId, CancellationToken ct);
    Task<RoleAssignmentResponse> AssignAsync(Guid userId, CreateRoleAssignmentRequest request, string actor, CancellationToken ct);
    Task<bool> RevokeAsync(Guid userId, Guid assignmentId, string actor, CancellationToken ct);
}

public sealed class EntitlementAdministrationService(
    EntitlementsDbContext db,
    IUserContextCache cache,
    TimeProvider timeProvider) : IEntitlementAdministrationService
{
    public async Task<IReadOnlyCollection<RoleResponse>> ListRolesAsync(CancellationToken ct)
    {
        var values = await db.Roles.AsNoTracking().OrderBy(x => x.RoleKey).ToArrayAsync(ct);
        return values.Select(Map).ToArray();
    }

    public async Task<RoleResponse?> GetRoleAsync(Guid id, CancellationToken ct)
    {
        var entity = await db.Roles.AsNoTracking().SingleOrDefaultAsync(x => x.RoleId == id, ct);
        return entity is null ? null : Map(entity);
    }

    public async Task<RoleResponse> CreateRoleAsync(CreateRoleRequest request, CancellationToken ct)
    {
        var entity = Role.Create(request.Key, request.Description, timeProvider.GetUtcNow());
        db.Roles.Add(entity);
        await db.SaveChangesAsync(ct);
        return Map(entity);
    }

    public async Task<RoleResponse?> UpdateRoleAsync(Guid id, UpdateRoleRequest request, CancellationToken ct)
    {
        var entity = await db.Roles.SingleOrDefaultAsync(x => x.RoleId == id, ct);
        if (entity is null) return null;
        entity.Update(request.Description, request.Status, request.Key);
        await TouchAssignedUsersAsync(id, ct);
        await db.SaveChangesAsync(ct);
        return Map(entity);
    }

    public async Task<bool> RetireRoleAsync(Guid id, CancellationToken ct)
    {
        var entity = await db.Roles.SingleOrDefaultAsync(x => x.RoleId == id, ct);
        if (entity is null) return false;
        entity.Update(entity.Description, "retired");
        await TouchAssignedUsersAsync(id, ct);
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<IReadOnlyCollection<RoleAssignmentResponse>> ListAssignmentsAsync(
        Guid userId,
        CancellationToken ct)
    {
        var values = await db.RoleAssignments.AsNoTracking()
            .Include(x => x.Role)
            .Where(x => x.UserId == userId)
            .OrderBy(x => x.AssignmentId)
            .ToArrayAsync(ct);
        return values.Select(x => Map(x)).ToArray();
    }

    public async Task<RoleAssignmentResponse> AssignAsync(
        Guid userId,
        CreateRoleAssignmentRequest request,
        string actor,
        CancellationToken ct)
    {
        if (request.RoleId == Guid.Empty) throw new ArgumentException("RoleId is required.");
        var user = await db.Users.SingleOrDefaultAsync(x => x.UserId == userId, ct)
            ?? throw new KeyNotFoundException("User was not found.");
        var role = await db.Roles.SingleOrDefaultAsync(
            x => x.RoleId == request.RoleId,
            ct) ?? throw new KeyNotFoundException("Role was not found.");
        var entity = RoleAssignment.Create(
            userId,
            request.RoleId,
            request.EffectiveFrom,
            request.EffectiveTo,
            actor,
            timeProvider.GetUtcNow());

        user.IncrementContextVersion();
        db.RoleAssignments.Add(entity);
        await db.SaveChangesAsync(ct);
        await cache.RemoveAsync(userId, ct);
        return Map(entity, role.RoleKey);
    }

    public async Task<bool> RevokeAsync(
        Guid userId,
        Guid assignmentId,
        string actor,
        CancellationToken ct)
    {
        var user = await db.Users.SingleOrDefaultAsync(x => x.UserId == userId, ct);
        var assignment = await db.RoleAssignments.SingleOrDefaultAsync(
            x => x.UserId == userId && x.AssignmentId == assignmentId,
            ct);
        if (user is null || assignment is null) return false;

        assignment.Revoke(actor, timeProvider.GetUtcNow());
        user.IncrementContextVersion();
        await db.SaveChangesAsync(ct);
        await cache.RemoveAsync(userId, ct);
        return true;
    }

    private async Task TouchAssignedUsersAsync(Guid roleId, CancellationToken ct)
    {
        var users = await db.Users
            .Where(x => x.Assignments.Any(a => a.RoleId == roleId))
            .ToListAsync(ct);
        foreach (var user in users)
        {
            user.IncrementContextVersion();
            await cache.RemoveAsync(user.UserId, ct);
        }
    }

    private static RoleResponse Map(Role value) =>
        new(value.RoleId, value.RoleKey, value.Description, value.Status);

    private static RoleAssignmentResponse Map(RoleAssignment value, string? roleKey = null) => new(
        value.AssignmentId,
        value.UserId,
        value.RoleId,
        roleKey ?? value.Role.RoleKey,
        value.EffectiveFrom,
        value.EffectiveTo,
        value.AssignedBy,
        value.AssignedAt,
        value.RevokedAt,
        value.RevokedBy);
}
