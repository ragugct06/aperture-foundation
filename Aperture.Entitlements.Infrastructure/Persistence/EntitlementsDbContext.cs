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
            // SQL schema has no status or context_version columns
            entity.Property(x => x.Status);
            entity.Property(x => x.ContextVersion);
            entity.HasIndex(x => x.Email).IsUnique().HasDatabaseName("app_user_email_key");
        });

        modelBuilder.Entity<Role>(entity =>
        {
            entity.ToTable("role");
            entity.HasKey(x => x.RoleId);
            entity.Property(x => x.RoleId).HasColumnName("role_id");
            // SQL schema uses "name" — map RoleKey to that column; Description/Status/CreatedAt not in schema
            entity.Property(x => x.RoleKey).HasColumnName("name").HasMaxLength(100);
            entity.Property(x => x.Description);
            entity.Property(x => x.Status);
            entity.Property(x => x.CreatedAt);
            entity.HasIndex(x => x.RoleKey).IsUnique().HasDatabaseName("role_name_key");
        });

        modelBuilder.Entity<RoleAssignment>(entity =>
        {
            entity.ToTable("role_assignment");
            entity.HasKey(x => x.AssignmentId);
            entity.Property(x => x.AssignmentId).HasColumnName("assignment_id");
            entity.Property(x => x.UserId).HasColumnName("user_id");
            entity.Property(x => x.RoleId).HasColumnName("role_id");
            // SQL schema has only assignment_id, user_id, role_id
            entity.Property(x => x.EffectiveFrom);
            entity.Property(x => x.EffectiveTo);
            entity.Property(x => x.AssignedBy);
            entity.Property(x => x.AssignedAt);
            entity.Property(x => x.RevokedAt);
            entity.Property(x => x.RevokedBy);
            entity.HasOne(x => x.User).WithMany(x => x.Assignments).HasForeignKey(x => x.UserId);
            entity.HasOne(x => x.Role).WithMany(x => x.Assignments).HasForeignKey(x => x.RoleId);
            entity.HasIndex(x => new { x.UserId, x.RoleId }).HasDatabaseName("idx_role_assignment_user");
        });
    }
}
