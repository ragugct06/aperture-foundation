using Aperture.Entitlements.Infrastructure.Services;
using Aperture.Entitlements.Contracts;
using Microsoft.AspNetCore.Mvc;

namespace Aperture.Entitlements.Api.Controllers;

[ApiController]
[Route("api/authorization/administration/role-assignments")]
public sealed class AuthorizationAdministrationController(
    IEntitlementAdministrationService service)
    : AdminControllerBase
{
    [HttpPost]
    public async Task<ActionResult<RoleAssignmentResponse>> Assign(
        CreateAdministrativeRoleAssignmentRequest request,
        CancellationToken ct)
    {
        if (request.UserId == Guid.Empty || request.RoleId == Guid.Empty)
        {
            return BadRequest(new ProblemDetails
            {
                Title = "UserId and RoleId are required",
                Status = StatusCodes.Status400BadRequest
            });
        }

        var result = await service.AssignAsync(
            request.UserId,
            new CreateRoleAssignmentRequest
            {
                RoleId = request.RoleId,
                EffectiveFrom = request.EffectiveFrom,
                EffectiveTo = request.EffectiveTo
            },
            AuthenticatedActor,
            ct);
        return Created(
            $"/entitlement/v1/users/{request.UserId}/role-assignments/{result.AssignmentId}",
            result);
    }
}
