using System.ComponentModel.DataAnnotations;
using System;
using System.Collections.Generic;

namespace Aperture.Entitlements.Contracts;

public sealed class ResolveUserRequest
{
    [Required, StringLength(100)]
    public string FirstName { get; init; } = string.Empty;

    [Required, StringLength(100)]
    public string LastName { get; init; } = string.Empty;

    [Required, EmailAddress, StringLength(320)]
    public string Email { get; init; } = string.Empty;

    [Required, RegularExpression("^(active|suspended|deprovisioned)$")]
    public string Status { get; init; } = "active";
}

public sealed record ResolveUserResponse(Guid UserId, bool Created);

public sealed record UserContextResponse(
    Guid UserId,
    string FirstName,
    string LastName,
    string Email,
    string Status,
    IReadOnlyCollection<string> Roles,
    long Version,
    string ETag);

public sealed record UserSummaryResponse(
    Guid UserId,
    string FirstName,
    string LastName,
    string Email,
    string Status);

public sealed class AddUserRequest
{
    [Required, StringLength(100)]
    public string FirstName { get; init; } = string.Empty;

    [Required, StringLength(100)]
    public string LastName { get; init; } = string.Empty;

    [Required, EmailAddress, StringLength(320)]
    public string Email { get; init; } = string.Empty;

    [Required, RegularExpression("^(active|suspended|deprovisioned)$")]
    public string Status { get; init; } = "active";
}

public sealed class UpdateUserRequest
{
    public Guid UserId { get; init; }

    [Required, StringLength(100)]
    public string FirstName { get; init; } = string.Empty;

    [Required, StringLength(100)]
    public string LastName { get; init; } = string.Empty;

    [Required, EmailAddress, StringLength(320)]
    public string Email { get; init; } = string.Empty;

    [Required, RegularExpression("^(active|suspended|deprovisioned)$")]
    public string Status { get; init; } = "active";
}

public sealed class CreateRoleRequest
{
    [Required, RegularExpression("^[A-Za-z][A-Za-z0-9._-]{1,99}$")]
    public string Key { get; init; } = string.Empty;

    [StringLength(500)]
    public string? Description { get; init; }
}

public sealed class UpdateRoleRequest
{
    [RegularExpression("^[A-Za-z][A-Za-z0-9._-]{1,99}$")]
    public string? Key { get; init; }

    [Required, StringLength(500)]
    public string Description { get; init; } = string.Empty;

    [Required, RegularExpression("^(active|retired)$")]
    public string Status { get; init; } = "active";
}

public sealed record RoleResponse(
    Guid RoleId,
    string Key,
    string Description,
    string Status);

public sealed class CreateRoleAssignmentRequest
{
    public Guid RoleId { get; init; }
    public DateOnly EffectiveFrom { get; init; }
    public DateOnly? EffectiveTo { get; init; }
}

public sealed record RoleAssignmentResponse(
    Guid AssignmentId,
    Guid UserId,
    Guid RoleId,
    string RoleKey,
    DateOnly EffectiveFrom,
    DateOnly? EffectiveTo,
    string AssignedBy,
    DateTimeOffset AssignedAt,
    DateTimeOffset? RevokedAt,
    string? RevokedBy);

public sealed class CreateAdministrativeRoleAssignmentRequest
{
    public Guid UserId { get; init; }
    public Guid RoleId { get; init; }
    public DateOnly EffectiveFrom { get; init; }
    public DateOnly? EffectiveTo { get; init; }
}
