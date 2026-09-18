using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;

namespace Aperture.Entitlements.Api.Controllers;

public abstract class AdminControllerBase : ControllerBase
{
    protected string AuthenticatedActor =>
        User.FindFirstValue("preferred_username") ??
        User.FindFirstValue(ClaimTypes.Email) ??
        User.Identity?.Name ??
        throw new UnauthorizedAccessException("An authenticated user identity is required.");
}
