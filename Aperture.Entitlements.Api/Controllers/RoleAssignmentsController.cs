using Aperture.Entitlements.Infrastructure.Services;
using Aperture.Entitlements.Contracts;
using Microsoft.AspNetCore.Mvc;

namespace Aperture.Entitlements.Api.Controllers;

[ApiController]
[Route("entitlement/v1/users/{userId:guid}/role-assignments")]
public sealed class RoleAssignmentsController(
    IEntitlementAdministrationService service)
    : AdminControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IReadOnlyCollection<RoleAssignmentResponse>>> List(
        Guid userId,
        CancellationToken ct)
    {
        return Ok(await service.ListAssignmentsAsync(userId, ct));
    }

    [HttpPost]
    public async Task<ActionResult<RoleAssignmentResponse>> Assign(
        Guid userId,
        CreateRoleAssignmentRequest request,
        CancellationToken ct)
    {
        var result = await service.AssignAsync(userId, request, AuthenticatedActor, ct);
        return CreatedAtAction(nameof(List), new { userId }, result);
    }

    [HttpDelete("{assignmentId:guid}")]
    public async Task<IActionResult> Revoke(
        Guid userId,
        Guid assignmentId,
        CancellationToken ct)
    {
        return await service.RevokeAsync(userId, assignmentId, AuthenticatedActor, ct)
            ? NoContent()
            : NotFound();
    }
}
