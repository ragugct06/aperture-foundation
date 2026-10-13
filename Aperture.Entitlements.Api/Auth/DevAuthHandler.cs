// DEV ONLY - inactive unless DevAuth:Enabled is true (false in appsettings.json).
// When DevAuth:Enabled is true in appsettings.Development.json, every incoming
// request is auto-authenticated with a hardcoded identity so the team can call
// APIs locally without needing a real Azure AD token or running AAD infrastructure.
//
// The fake claims mirror what the real JWT would carry so the rest of the
// pipeline (ITenantContext, RequireEntitlement, audit stamping) behaves the
// same as production. Change DevAuth:UserId and DevAuth:ManufacturerId in
// appsettings.Development.json to simulate different callers.
//
// This file is compiled in all configurations but the handler is only
// registered when DevAuth:Enabled = true (see Program.cs).

using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;
using System.Security.Claims;
using System.Text.Encodings.Web;

namespace Aperture.Entitlements.Api.Auth;

public sealed class DevAuthOptions : AuthenticationSchemeOptions { }

public sealed class DevAuthHandler : AuthenticationHandler<DevAuthOptions>
{
    private readonly IConfiguration _configuration;

    public DevAuthHandler(
        IOptionsMonitor<DevAuthOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder,
        IConfiguration configuration)
        : base(options, logger, encoder)
    {
        _configuration = configuration;
    }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var userId = _configuration["DevAuth:UserId"] ?? "dev-user-001";
        var manufacturerId = _configuration["DevAuth:ManufacturerId"]
                             ?? "a0000000-0000-0000-0000-000000000001";

        // Claims match what the real JWT pipeline produces so ITenantContext
        // and audit fields receive valid values during local testing.
        // "tid" is the claim JwtClaimTenantResolver reads to resolve the tenant —
        // without it ITenantContext.IsResolved stays false and the RLS interceptor
        // skips the SET, causing Postgres to throw 42704 on the RLS policy.
        var email = _configuration["DevAuth:UserEmail"] ?? "dev@aperture.local";

        var claims = new[]
        {
            new Claim("sub", userId),
            new Claim("oid", userId),
            new Claim("tid", manufacturerId),
            new Claim("manufacturer_id", manufacturerId),
            new Claim("preferred_username", email),  // forwarded by SDK to Entitlement service
            new Claim(ClaimTypes.Email, email),
            new Claim(ClaimTypes.Name, userId),
            new Claim(ClaimTypes.Role, "CopayAdmin")
        };

        var identity = new ClaimsIdentity(claims, Scheme.Name);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, Scheme.Name);

        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
