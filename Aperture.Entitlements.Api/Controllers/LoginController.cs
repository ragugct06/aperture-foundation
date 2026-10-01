using System.ComponentModel.DataAnnotations;
using Aperture.Entitlements.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace Aperture.Entitlements.Api.Controllers;

[ApiController]
[Route("entitlement/v1/login")]
public sealed class LoginController(LoginService login) : ControllerBase
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
            return Unauthorized(new LoginResponse(false, "Invalid username or password.", null, []));

        return Ok(new LoginResponse(
            true,
            "Authentication successful.",
            authenticated.Email,
            authenticated.Roles));
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
    string? Email,
    IReadOnlyCollection<string> Roles);
