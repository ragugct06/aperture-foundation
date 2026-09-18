using Aperture.Entitlements.Domain;

namespace Aperture.Entitlements.Tests;

public sealed class RoleAssignmentTests
{
    [Fact]
    public void Effective_to_is_exclusive_and_must_follow_start()
    {
        var date = new DateOnly(2026, 1, 1);
        var action = () => RoleAssignment.Create(
            Guid.NewGuid(), Guid.NewGuid(), date, date, "admin-user", DateTimeOffset.UtcNow);
        Assert.Throws<ArgumentException>(action);
    }
}
