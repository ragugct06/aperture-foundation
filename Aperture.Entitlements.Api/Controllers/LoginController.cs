using System.ComponentModel.DataAnnotations;
using Aperture.Entitlements.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;

namespace Aperture.Entitlements.Api.Controllers;

[ApiController]
[Route("entitlement/v1/login")]
public sealed class LoginController(
    LoginService login,
    ISessionService sessions,
    IOptions<LoginSessionOptions> sessionOptions) : ControllerBase
{
    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting("login")]
    [ProducesResponseType<LoginResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<LoginResponse>(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<LoginResponse>> Login(LoginRequest request, CancellationToken ct)
    {
        Response.Headers.CacheControl = "no-store";
        var authenticated = await login.AuthenticateAsync(request.Username, request.Password, ct);
        if (authenticated is null)
            return Unauthorized(new LoginResponse(
                false,
                "Invalid username or password.",
                null,
                null,
                null,
                [],
                null,
                null));

        // APP-1417: foundation owns the session. The id goes back in the body for API consumers
        // (copay forwards it to the browser) and as a cookie for callers that talk to foundation
        // directly. Resolve it later with GET entitlement/v1/session.
        var session = await sessions.CreateAsync(authenticated, ct);
        Response.Cookies.Append(sessionOptions.Value.CookieName, session.SessionId, new CookieOptions
        {
            HttpOnly = true,
            Secure = Request.IsHttps,
            SameSite = SameSiteMode.Strict,
            Path = "/"
        });

        return Ok(new LoginResponse(
            true,
            "Authentication successful.",
            authenticated.FirstName,
            authenticated.LastName,
            authenticated.Email,
            authenticated.Roles,
            session.SessionId,
            session.ExpiresAt));
    }
}

public sealed class LoginRequest
{
    [Required, StringLength(320)]
    public string Username { get; init; } = "";
    [Required, StringLength(1024)]
    public string Password { get; init; } = "";
}

public sealed record LoginResponse(
    bool Authenticated,
    string Message,
    string? FirstName,
    string? LastName,
    string? Email,
    IReadOnlyCollection<string> Roles,
    string? SessionId,
    DateTimeOffset? ExpiresAt);
