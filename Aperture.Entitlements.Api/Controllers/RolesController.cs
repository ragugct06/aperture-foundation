using Aperture.Entitlements.Infrastructure.Services;
using Aperture.Entitlements.Contracts;
using Microsoft.AspNetCore.Mvc;

namespace Aperture.Entitlements.Api.Controllers;

[ApiController]
[Route("entitlement/v1/roles")]
public sealed class RolesController(IEntitlementAdministrationService service) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IReadOnlyCollection<RoleResponse>>> List(CancellationToken ct)
    {
        return Ok(await service.ListRolesAsync(ct));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<RoleResponse>> Get(Guid id, CancellationToken ct)
    {
        var result = await service.GetRoleAsync(id, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpPost]
    public async Task<ActionResult<RoleResponse>> Create(CreateRoleRequest request, CancellationToken ct)
    {
        var result = await service.CreateRoleAsync(request, ct);
        return CreatedAtAction(nameof(Get), new { id = result.RoleId }, result);
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<RoleResponse>> Update(
        Guid id,
        UpdateRoleRequest request,
        CancellationToken ct)
    {
        var result = await service.UpdateRoleAsync(id, request, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Retire(Guid id, CancellationToken ct)
    {
        return await service.RetireRoleAsync(id, ct) ? NoContent() : NotFound();
    }
}
