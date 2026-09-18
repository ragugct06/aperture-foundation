using Aperture.Entitlements.Infrastructure.Caching;
using Aperture.Entitlements.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using System;

namespace Aperture.Entitlements.Infrastructure.Services;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddEntitlementsInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var connection = configuration.GetConnectionString("EntitlementsDatabase")
            ?? throw new InvalidOperationException(
                "ConnectionStrings:EntitlementsDatabase is required.");
        var redis = configuration.GetConnectionString("Redis")
            ?? throw new InvalidOperationException("ConnectionStrings:Redis is required.");

        services.AddDbContext<EntitlementsDbContext>(options =>
            options.UseNpgsql(connection, npgsql => npgsql.MigrationsHistoryTable(
                "__EFMigrationsHistory",
                "entitlement")));
        services.AddStackExchangeRedisCache(options =>
        {
            options.Configuration = redis;
            options.InstanceName = "Aperture:Entitlements:";
        });
        services.AddSingleton(TimeProvider.System);
        services.AddScoped<IUserContextCache, UserContextCache>();
        services.AddScoped<IUserService, UserService>();
        services.AddScoped<IEntitlementAdministrationService, EntitlementAdministrationService>();
        return services;
    }
}
