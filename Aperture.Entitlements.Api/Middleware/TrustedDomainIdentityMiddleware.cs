using System.Security.Claims;
using Microsoft.Extensions.Options;

namespace Aperture.Entitlements.Api.Middleware;

public sealed class TrustedDomainIdentityOptions
{
    public bool Enabled { get; set; } = true;
    public string VerifiedHeader { get; set; } = "X-Aperture-Identity-Verified";
    public string EmailHeader { get; set; } = "X-Aperture-User-Email";
}

public sealed class TrustedDomainIdentityMiddleware(
    RequestDelegate next,
    IOptions<TrustedDomainIdentityOptions> options,
    ILogger<TrustedDomainIdentityMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        if (options.Value.Enabled && context.User.Identity?.IsAuthenticated != true)
        {
            ApplyTrustedIdentity(context);
        }

        await next(context);
    }

    private void ApplyTrustedIdentity(HttpContext context)
    {
        var settings = options.Value;
        if (!string.Equals(
                context.Request.Headers[settings.VerifiedHeader].ToString(),
                "true",
                StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var email = context.Request.Headers[settings.EmailHeader].ToString().Trim();
        if (email.Length == 0)
        {
            return;
        }

        var claims = new List<Claim>
        {
            new("preferred_username", email),
            new(ClaimTypes.Email, email),
            new(ClaimTypes.Name, email)
        };

        context.User = new ClaimsPrincipal(new ClaimsIdentity(
            claims,
            "TrustedDomainApi",
            ClaimTypes.Name,
            ClaimTypes.Role));
        logger.LogDebug("Applied trusted Domain API identity for {Email}.", email);
    }
}

public sealed class AuthenticatedUserMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        if (IsPublicPath(context.Request.Path) ||
            context.User.Identity?.IsAuthenticated == true)
        {
            await next(context);
            return;
        }

        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        await context.Response.WriteAsJsonAsync(new Microsoft.AspNetCore.Mvc.ProblemDetails
        {
            Status = StatusCodes.Status401Unauthorized,
            Title = "Authenticated user required",
            Detail = "The Domain API did not propagate a verified authenticated user."
        });
    }

    private static bool IsPublicPath(PathString path) =>
        path.StartsWithSegments("/health") ||
        path.StartsWithSegments("/swagger");
}
