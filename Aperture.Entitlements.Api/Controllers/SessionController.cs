using Aperture.Entitlements.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

namespace Aperture.Entitlements.Api.Controllers;

/// <summary>
/// APP-1417: resolves and ends the login sessions that <see cref="LoginController"/> creates.
/// Consumer services (copay today) call GET on every request they cannot answer from their own
/// short-lived cache, passing the session id from the X-Aperture-Session header or the cookie.
/// Both endpoints authenticate the caller by the session itself, so they bypass the trusted-identity
/// guard with AllowAnonymous.
/// </summary>
[ApiController]
[Route("entitlement/v1/session")]
public sealed class SessionController(
    ISessionService sessions,
    IOptions<LoginSessionOptions> options) : ControllerBase
{
    [HttpGet]
    [AllowAnonymous]
    [ProducesResponseType<SessionResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<SessionResponse>(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<SessionResponse>> Get(CancellationToken ct)
    {
        Response.Headers.CacheControl = "no-store";
        var session = await sessions.GetAsync(ResolveSessionId(), ct);
        if (session is null)
            return Unauthorized(SessionResponse.Anonymous("No active session."));

        return Ok(SessionResponse.From(session));
    }

    [HttpDelete]
    [HttpPost("~/entitlement/v1/logout")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> End(CancellationToken ct)
    {
        Response.Headers.CacheControl = "no-store";
        await sessions.RevokeAsync(ResolveSessionId(), ct);
        Response.Cookies.Delete(options.Value.CookieName, new CookieOptions { Path = "/" });
        return NoContent();
    }

    private string? ResolveSessionId()
    {
        var header = Request.Headers[SessionService.HeaderName].ToString();
        if (!string.IsNullOrWhiteSpace(header)) return header.Trim();
        return Request.Cookies.TryGetValue(options.Value.CookieName, out var cookie) ? cookie : null;
    }
}

public sealed record SessionResponse(
    bool Authenticated,
    string Message,
    string? SessionId,
    Guid? UserId,
    string? FirstName,
    string? LastName,
    string? Email,
    IReadOnlyCollection<string> Roles,
    DateTimeOffset? ExpiresAt)
{
    public static SessionResponse Anonymous(string message) =>
        new(false, message, null, null, null, null, null, [], null);

    public static SessionResponse From(UserSession session) =>
        new(true, "Session active.", session.SessionId, session.UserId, session.FirstName,
            session.LastName, session.Email, session.Roles, session.ExpiresAt);
}
