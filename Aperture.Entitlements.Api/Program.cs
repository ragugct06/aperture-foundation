using Aperture.Entitlements.Api.Middleware;
using Aperture.Entitlements.Infrastructure.Services;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);
if (!builder.Environment.IsDevelopment()) EnsureNoPlaceholders(builder.Configuration);

builder.Services.Configure<TrustedDomainIdentityOptions>(
    builder.Configuration.GetSection("TrustedDomainIdentity"));

builder.Services.AddEntitlementsInfrastructure(builder.Configuration);
builder.Services.AddControllers();
builder.Services.AddHealthChecks();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Aperture Entitlements API",
        Version = "v1"
    });
    if (!builder.Environment.IsDevelopment()) return;

    AddDevelopmentHeader(
        options,
        "VerifiedIdentity",
        "X-Aperture-Identity-Verified",
        "Enter true. This simulates the trusted Domain API identity marker.");
    AddDevelopmentHeader(
        options,
        "UserEmail",
        "X-Aperture-User-Email",
        "Email of the user already authenticated by the Domain API.");
    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        [Reference("VerifiedIdentity")] = [],
        [Reference("UserEmail")] = []
    });
});

var app = builder.Build();
app.UseMiddleware<CorrelationMiddleware>();
app.UseMiddleware<ExceptionMiddleware>();
app.UseMiddleware<TrustedDomainIdentityMiddleware>();
app.UseMiddleware<AuthenticatedUserMiddleware>();
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.MapHealthChecks("/health");
app.MapControllers();
app.Run();

static void AddDevelopmentHeader(
    Swashbuckle.AspNetCore.SwaggerGen.SwaggerGenOptions options,
    string id,
    string headerName,
    string description) => options.AddSecurityDefinition(id, new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.ApiKey,
        In = ParameterLocation.Header,
        Name = headerName,
        Description = description
    });

static OpenApiSecurityScheme Reference(string id) => new()
{
    Reference = new OpenApiReference
    {
        Type = ReferenceType.SecurityScheme,
        Id = id
    }
};

static void EnsureNoPlaceholders(IConfiguration configuration)
{
    var invalid = configuration.AsEnumerable()
        .Where(x => x.Value?.Contains("REPLACE", StringComparison.OrdinalIgnoreCase) == true)
        .Select(x => x.Key)
        .ToArray();
    if (invalid.Length > 0)
    {
        throw new InvalidOperationException(
            $"Production configuration contains placeholders: {string.Join(", ", invalid)}");
    }
}

public partial class Program { }
