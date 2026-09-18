using Aperture.Entitlements.Infrastructure.Services;
using Aperture.Entitlements.Contracts;
using Microsoft.AspNetCore.Mvc;

namespace Aperture.Entitlements.Api.Controllers;

[ApiController]
[Route("entitlement/v1/users")]
public sealed class UsersController(IUserService users) : ControllerBase
{
    [HttpPost("/entitlement/v1/users:resolve", Name = "resolveUser")]
    [ProducesResponseType<ResolveUserResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ResolveUserResponse>(StatusCodes.Status201Created)]
    public async Task<ActionResult<ResolveUserResponse>> Resolve(
        ResolveUserRequest request,
        CancellationToken ct)
    {
        var result = await users.ResolveAsync(request, ct);
        return result.Created ? StatusCode(StatusCodes.Status201Created, result) : Ok(result);
    }

    [HttpGet("{userId:guid}/context", Name = "getUserContext")]
    [ProducesResponseType<UserContextResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status304NotModified)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<UserContextResponse>> Context(Guid userId, CancellationToken ct)
    {
        var result = await users.GetContextAsync(userId, ct);
        if (result is null) return NotFound();
        if (Request.Headers["If-None-Match"].Any(x => x == result.ETag))
        {
            return StatusCode(StatusCodes.Status304NotModified);
        }

        Response.Headers["ETag"] = result.ETag;
        return Ok(result);
    }
}
