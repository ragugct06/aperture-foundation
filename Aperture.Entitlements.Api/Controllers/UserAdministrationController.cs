using Aperture.Entitlements.Infrastructure.Services;
using Aperture.Entitlements.Contracts;
using Microsoft.AspNetCore.Mvc;

namespace Aperture.Entitlements.Api.Controllers;

[ApiController]
[Route("api/users")]
public sealed class UserAdministrationController(IUserService users) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult> Find(
        [FromQuery] string? email,
        [FromQuery] string? ids,
        CancellationToken ct)
    {
        if (!string.IsNullOrWhiteSpace(email) && string.IsNullOrWhiteSpace(ids))
        {
            var user = await users.FindByEmailAsync(email, ct);
            return user is null ? NotFound() : Ok(user);
        }

        if (!string.IsNullOrWhiteSpace(ids) && string.IsNullOrWhiteSpace(email))
        {
            if (!TryParseIds(ids, out var userIds))
            {
                return BadRequest(new ProblemDetails
                {
                    Title = "Invalid user ids",
                    Detail = "The ids query parameter must be a comma-separated list of GUIDs.",
                    Status = StatusCodes.Status400BadRequest
                });
            }

            return Ok(await users.FindByIdsAsync(userIds, ct));
        }

        return BadRequest(new ProblemDetails
        {
            Title = "Invalid query",
            Detail = "Supply exactly one of the email or ids query parameters.",
            Status = StatusCodes.Status400BadRequest
        });
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<UserSummaryResponse>> FindById(Guid id, CancellationToken ct)
    {
        var user = await users.FindByIdAsync(id, ct);
        return user is null ? NotFound() : Ok(user);
    }

    [HttpGet("search")]
    public async Task<ActionResult<IReadOnlyCollection<Guid>>> SearchIds(
        [FromQuery] string q,
        CancellationToken ct)
    {
        return Ok(await users.SearchIdsAsync(q, ct));
    }

    [HttpPost]
    public async Task<ActionResult<UserSummaryResponse>> Add(
        AddUserRequest request,
        CancellationToken ct)
    {
        var user = await users.AddAsync(request, ct);
        return CreatedAtAction(nameof(FindById), new { id = user.UserId }, user);
    }

    [HttpPatch]
    public async Task<ActionResult<UserSummaryResponse>> Update(
        UpdateUserRequest request,
        CancellationToken ct)
    {
        var user = await users.UpdateAsync(request, ct);
        return user is null ? NotFound() : Ok(user);
    }

    [HttpPatch("{id:guid}")]
    public async Task<ActionResult<UserSummaryResponse>> UpdateById(
        Guid id,
        UpdateUserRequest request,
        CancellationToken ct)
    {
        if (request.UserId != Guid.Empty && request.UserId != id)
        {
            return BadRequest(new ProblemDetails
            {
                Title = "User id mismatch",
                Detail = "The route and request user ids must match.",
                Status = StatusCodes.Status400BadRequest
            });
        }

        var normalized = new UpdateUserRequest
        {
            UserId = id,
            FirstName = request.FirstName,
            LastName = request.LastName,
            Email = request.Email,
            Status = request.Status
        };
        var user = await users.UpdateAsync(normalized, ct);
        return user is null ? NotFound() : Ok(user);
    }

    private static bool TryParseIds(string value, out IReadOnlyCollection<Guid> ids)
    {
        var parsed = new List<Guid>();
        foreach (var part in value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (!Guid.TryParse(part, out var id) || id == Guid.Empty)
            {
                ids = [];
                return false;
            }

            parsed.Add(id);
        }

        ids = parsed.Distinct().ToArray();
        return ids.Count > 0;
    }
}
