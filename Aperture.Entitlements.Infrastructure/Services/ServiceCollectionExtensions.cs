using Aperture.Entitlements.Infrastructure.Caching;
using Aperture.Entitlements.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using System;

namespace Aperture.Entitlements.Infrastructure.Services;

public static class ServiceCollectionExtensions
{
    /// <param name="requireDistributedCache">
    /// When true (every deployed environment), startup fails if ConnectionStrings:Redis is missing
    /// instead of silently using an in-process cache that replicas would not share (APP-1417).
    /// </param>
    public static IServiceCollection AddEntitlementsInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        bool requireDistributedCache = false)
    {
        var connection = Environment.GetEnvironmentVariable("ConnectionStrings__EntitlementsDatabase")
            ?? configuration.GetConnectionString("EntitlementsDatabase")
            ?? throw new InvalidOperationException(
                "ConnectionStrings:EntitlementsDatabase is required.");

        services.AddDbContext<EntitlementsDbContext>(options =>
            options.UseNpgsql(connection, npgsql => npgsql.MigrationsHistoryTable(
                "__EFMigrationsHistory",
                "entitlement")));

        // APP-1417: login sessions (and the user-context cache) live in the distributed cache.
        // Redis in deployed environments; the gitops chart injects ConnectionStrings__Redis in the
        // StackExchange.Redis form "host:port,password=...,ssl=True,user=..." (ssl=True = rediss).
        var redis = Environment.GetEnvironmentVariable("ConnectionStrings__Redis")
            ?? configuration.GetConnectionString("Redis");
        if (!string.IsNullOrWhiteSpace(redis))
        {
            services.AddStackExchangeRedisCache(options =>
            {
                options.Configuration = redis;
                options.InstanceName = "aperture-foundation:";
            });
        }
        else if (requireDistributedCache)
        {
            throw new InvalidOperationException(
                "ConnectionStrings:Redis is required outside Development so login sessions are shared across replicas.");
        }
        else
        {
            services.AddDistributedMemoryCache();
        }

        services.Configure<LoginSessionOptions>(configuration.GetSection(LoginSessionOptions.SectionName));
        services.AddScoped<ISessionService, SessionService>();

        services.AddSingleton(TimeProvider.System);
        services.AddScoped<IUserContextCache, UserContextCache>();
        services.AddScoped<IUserService, UserService>();
        services.AddScoped<LoginService>();
        services.AddScoped<IEntitlementAdministrationService, EntitlementAdministrationService>();
        return services;
    }
}
