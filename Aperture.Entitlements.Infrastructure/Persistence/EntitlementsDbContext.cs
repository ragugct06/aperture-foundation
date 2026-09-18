using Aperture.Entitlements.Domain;
using Microsoft.EntityFrameworkCore;

namespace Aperture.Entitlements.Infrastructure.Persistence;

public sealed class EntitlementsDbContext(DbContextOptions<EntitlementsDbContext> options)
    : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Role> Roles => Set<Role>();
    public DbSet<RoleAssignment> RoleAssignments => Set<RoleAssignment>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("entitlement");

        modelBuilder.Entity<User>(entity =>
        {
            entity.ToTable("app_user");
            entity.HasKey(x => x.UserId);
            entity.Property(x => x.UserId).HasColumnName("user_id");
            entity.Property(x => x.FirstName).HasColumnName("first_name").HasMaxLength(100);
            entity.Property(x => x.LastName).HasColumnName("last_name").HasMaxLength(100);
            entity.Property(x => x.Email).HasColumnName("email").HasMaxLength(320);
            entity.Property(x => x.Status).HasColumnName("status").HasMaxLength(20);
            entity.Property(x => x.ContextVersion).HasColumnName("context_version").IsConcurrencyToken();
            entity.HasIndex(x => x.Email).IsUnique().HasDatabaseName("uq_app_user_email");
        });

        modelBuilder.Entity<Role>(entity =>
        {
            entity.ToTable("app_role");
            entity.HasKey(x => x.RoleId);
            entity.Property(x => x.RoleId).HasColumnName("role_id");
            entity.Property(x => x.RoleKey).HasColumnName("role_key").HasMaxLength(100);
            entity.Property(x => x.Description).HasColumnName("description").HasMaxLength(500);
            entity.Property(x => x.Status).HasColumnName("status").HasMaxLength(20);
            entity.Property(x => x.CreatedAt).HasColumnName("created_at");
            entity.HasIndex(x => x.RoleKey).IsUnique().HasDatabaseName("uq_app_role_key");
        });

        modelBuilder.Entity<RoleAssignment>(entity =>
        {
            entity.ToTable("role_assignment");
            entity.HasKey(x => x.AssignmentId);
            entity.Property(x => x.AssignmentId).HasColumnName("assignment_id");
            entity.Property(x => x.UserId).HasColumnName("user_id");
            entity.Property(x => x.RoleId).HasColumnName("role_id");
            entity.Property(x => x.EffectiveFrom).HasColumnName("effective_from");
            entity.Property(x => x.EffectiveTo).HasColumnName("effective_to");
            entity.Property(x => x.AssignedBy).HasColumnName("assigned_by").HasMaxLength(200);
            entity.Property(x => x.AssignedAt).HasColumnName("assigned_at");
            entity.Property(x => x.RevokedAt).HasColumnName("revoked_at");
            entity.Property(x => x.RevokedBy).HasColumnName("revoked_by").HasMaxLength(200);
            entity.HasOne(x => x.User).WithMany(x => x.Assignments).HasForeignKey(x => x.UserId);
            entity.HasOne(x => x.Role).WithMany(x => x.Assignments).HasForeignKey(x => x.RoleId);
            entity.HasIndex(x => new { x.UserId, x.RoleId, x.EffectiveFrom })
                .HasDatabaseName("ix_role_assignment_lookup");
        });
    }
}
