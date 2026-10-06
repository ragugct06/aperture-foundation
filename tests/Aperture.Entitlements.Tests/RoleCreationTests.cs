using System.Net;
using System.Net.Http.Json;
using Aperture.Entitlements.Api.Controllers;
using Aperture.Entitlements.Api.Middleware;
using Aperture.Entitlements.Domain;
using Aperture.Entitlements.Infrastructure.Persistence;
using Aperture.Entitlements.Infrastructure.Services;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Aperture.Entitlements.Tests;

public sealed class RoleCreationTests
{
    [Theory]
    [InlineData("{\"key\":\"Admin\"}")]
    [InlineData("{\"key\":\"Admin\",\"description\":null}")]
    [InlineData("{\"key\":\"Admin\",\"description\":\"\"}")]
    [InlineData("{\"key\":\"Admin\",\"description\":\"dup check\"}")]
    public async Task Duplicate_role_returns_409_regardless_of_description(string json)
    {
        await using var app = CreateApplication();
        await app.StartAsync();
        using var client = CreateClient(app);
        using var body = new StringContent(json, System.Text.Encoding.UTF8, "application/json");

        using var response = await client.PostAsync("/entitlement/v1/roles", body);

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        await using var scope = app.Services.CreateAsyncScope();
        Assert.Equal(1, await scope.ServiceProvider.GetRequiredService<EntitlementsDbContext>().Roles.CountAsync());
    }

    [Theory]
    [InlineData("{\"key\":\"Specialist\"}")]
    [InlineData("{\"key\":\"Specialist\",\"description\":null}")]
    [InlineData("{\"key\":\"Specialist\",\"description\":\"\"}")]
    public async Task New_role_accepts_absent_description_and_stores_empty_string(string json)
    {
        await using var app = CreateApplication();
        await app.StartAsync();
        using var client = CreateClient(app);
        using var body = new StringContent(json, System.Text.Encoding.UTF8, "application/json");

        using var response = await client.PostAsync("/entitlement/v1/roles", body);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        await using var scope = app.Services.CreateAsyncScope();
        var role = await scope.ServiceProvider.GetRequiredService<EntitlementsDbContext>().Roles
            .SingleAsync(x => x.RoleKey == "Specialist");
        Assert.Equal(string.Empty, role.Description);
    }

    [Fact]
    public async Task Description_length_limit_is_still_enforced()
    {
        await using var app = CreateApplication();
        await app.StartAsync();
        using var client = CreateClient(app);

        using var response = await client.PostAsJsonAsync("/entitlement/v1/roles",
            new { key = "Specialist", description = new string('a', 501) });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    private static WebApplication CreateApplication()
    {
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Services.AddControllers().AddApplicationPart(typeof(RolesController).Assembly);
        var databaseName = Guid.NewGuid().ToString();
        builder.Services.AddDbContext<EntitlementsDbContext>(options => options
            .UseInMemoryDatabase(databaseName)
            .AddInterceptors(new DuplicateRoleInterceptor()));
        builder.Services.AddSingleton<TimeProvider>(TimeProvider.System);
        builder.Services.AddSingleton<Aperture.Entitlements.Infrastructure.Caching.IUserContextCache, TestUserContextCache>();
        builder.Services.AddScoped<IEntitlementAdministrationService, EntitlementAdministrationService>();
        var app = builder.Build();
        app.UseMiddleware<ExceptionMiddleware>();
        app.MapControllers();
        using var scope = app.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<EntitlementsDbContext>();
        db.Roles.Add(Role.Create("Admin", "Administrator", DateTimeOffset.UtcNow));
        db.SaveChanges();
        return app;
    }

    private static HttpClient CreateClient(WebApplication app) => new()
    {
        BaseAddress = new Uri(app.Services.GetRequiredService<IServer>()
            .Features.Get<IServerAddressesFeature>()!.Addresses.Single())
    };

    // EF InMemory does not enforce the PostgreSQL unique index. Simulate its
    // SaveChanges failure while exercising real MVC validation and error handling.
    private sealed class DuplicateRoleInterceptor : SaveChangesInterceptor
    {
        public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(
            DbContextEventData eventData, InterceptionResult<int> result,
            CancellationToken cancellationToken = default)
        {
            var db = (EntitlementsDbContext)eventData.Context!;
            foreach (var entry in db.ChangeTracker.Entries<Role>().Where(x => x.State == EntityState.Added))
            {
                if (await db.Roles.AnyAsync(x => x.RoleKey == entry.Entity.RoleKey, cancellationToken))
                    throw new DbUpdateException("Duplicate role key.");
            }

            return result;
        }
    }
}
