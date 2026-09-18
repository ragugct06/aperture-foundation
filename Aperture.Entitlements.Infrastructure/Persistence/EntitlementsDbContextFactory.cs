using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Aperture.Entitlements.Infrastructure.Persistence;

public sealed class EntitlementsDbContextFactory
    : IDesignTimeDbContextFactory<EntitlementsDbContext>
{
    public EntitlementsDbContext CreateDbContext(string[] args)
    {
        var connection = Environment.GetEnvironmentVariable(
            "ConnectionStrings__EntitlementsDatabase");
        if (string.IsNullOrWhiteSpace(connection))
        {
            throw new InvalidOperationException(
                "Set ConnectionStrings__EntitlementsDatabase before running dotnet ef commands.");
        }

        return new EntitlementsDbContext(
            new DbContextOptionsBuilder<EntitlementsDbContext>()
                .UseNpgsql(connection, options => options.MigrationsHistoryTable(
                    "__EFMigrationsHistory",
                    "entitlement"))
                .Options);
    }
}
