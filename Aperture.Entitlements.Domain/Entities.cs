using System;
using System.Collections.Generic;

namespace Aperture.Entitlements.Domain;

public sealed class User
{
    private User() { }

    public Guid UserId { get; private set; }
    public string FirstName { get; private set; } = string.Empty;
    public string LastName { get; private set; } = string.Empty;
    public string Email { get; private set; } = string.Empty;
    public string Status { get; private set; } = "active";
    public long ContextVersion { get; private set; } = 1;
    public ICollection<RoleAssignment> Assignments { get; private set; } = [];

    public static User Create(string firstName, string lastName, string email, string status) => new()
    {
        UserId = Guid.NewGuid(),
        FirstName = Required(firstName, nameof(firstName)),
        LastName = Required(lastName, nameof(lastName)),
        Email = Required(email, nameof(email)).ToLowerInvariant(),
        Status = ValidateStatus(status)
    };

    public void Update(string firstName, string lastName, string email, string status)
    {
        FirstName = Required(firstName, nameof(firstName));
        LastName = Required(lastName, nameof(lastName));
        Email = Required(email, nameof(email)).ToLowerInvariant();
        Status = ValidateStatus(status);
    }

    public void IncrementContextVersion() => ContextVersion++;

    private static string Required(string value, string name) =>
        string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException($"{name} is required.")
            : value.Trim();

    private static string ValidateStatus(string status) => status switch
    {
        "active" or "suspended" or "deprovisioned" => status,
        _ => throw new ArgumentException("Status must be active, suspended, or deprovisioned.")
    };
}

public sealed class Role
{
    private Role() { }

    public Guid RoleId { get; private set; }
    public string RoleKey { get; private set; } = string.Empty;
    public string Description { get; private set; } = string.Empty;
    public string Status { get; private set; } = "active";
    public DateTimeOffset CreatedAt { get; private set; }
    public ICollection<RoleAssignment> Assignments { get; private set; } = [];

    public static Role Create(string key, string? description, DateTimeOffset now) => new()
    {
        RoleId = Guid.NewGuid(),
        RoleKey = key.Trim(),
        Description = description?.Trim() ?? string.Empty,
        CreatedAt = now
    };

    public void Update(string description, string status)
    {
        Description = description.Trim();
        Status = status;
    }
}

public sealed class RoleAssignment
{
    private RoleAssignment() { }

    public Guid AssignmentId { get; private set; }
    public Guid UserId { get; private set; }
    public User User { get; private set; } = null!;
    public Guid RoleId { get; private set; }
    public Role Role { get; private set; } = null!;
    public DateOnly EffectiveFrom { get; private set; }
    public DateOnly? EffectiveTo { get; private set; }
    public string AssignedBy { get; private set; } = string.Empty;
    public DateTimeOffset AssignedAt { get; private set; }
    public DateTimeOffset? RevokedAt { get; private set; }
    public string? RevokedBy { get; private set; }

    public static RoleAssignment Create(
        Guid userId,
        Guid roleId,
        DateOnly effectiveFrom,
        DateOnly? effectiveTo,
        string assignedBy,
        DateTimeOffset now)
    {
        if (effectiveFrom == default) throw new ArgumentException("EffectiveFrom is required.");
        if (effectiveTo is not null && effectiveTo <= effectiveFrom)
        {
            throw new ArgumentException("EffectiveTo must be later than EffectiveFrom.");
        }

        return new RoleAssignment
        {
            AssignmentId = Guid.NewGuid(),
            UserId = userId,
            RoleId = roleId,
            EffectiveFrom = effectiveFrom,
            EffectiveTo = effectiveTo,
            AssignedBy = assignedBy,
            AssignedAt = now
        };
    }

    public void Revoke(string revokedBy, DateTimeOffset now)
    {
        if (RevokedAt is not null) return;
        RevokedAt = now;
        RevokedBy = revokedBy;
    }
}

public sealed class EntitlementOutboxMessage
{
    private EntitlementOutboxMessage() { }

    public Guid EventId { get; private set; }
    public string EventType { get; private set; } = string.Empty;
    public Guid UserId { get; private set; }
    public string PayloadJson { get; private set; } = string.Empty;
    public DateTimeOffset OccurredAt { get; private set; }
    public DateTimeOffset? PublishedAt { get; private set; }
    public void MarkPublished(DateTimeOffset now) => PublishedAt ??= now;
}
