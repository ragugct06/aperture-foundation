using System.Security.Cryptography;
using Aperture.Entitlements.Api.Controllers;
using Aperture.Entitlements.Api.Middleware;
using Aperture.Entitlements.Domain;
using Aperture.Entitlements.Infrastructure.Persistence;
using Aperture.Entitlements.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Aperture.Entitlements.Tests;

public sealed class LoginTests
{
    [Theory]
    [InlineData(" TEST.USER ", "correct password", "active", true)]
    [InlineData("test.user", "wrong password", "active", false)]
    [InlineData("missing", "correct password", "active", false)]
    [InlineData("test.user", "correct password", "suspended", false)]
    [InlineData("test.user", "correct password", "deprovisioned", false)]
    [InlineData("test.user", "correct password ", "active", false)]
    public async Task Login_checks_credentials_and_status(string username, string password, string status, bool success)
    {
        await using var db = new EntitlementsDbContext(new DbContextOptionsBuilder<EntitlementsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var user = User.Create("Test", "User", "test@example.test", status);
        db.Users.Add(user);
        var salt = RandomNumberGenerator.GetBytes(16);
        db.UserCredentials.Add(new UserCredential
        {
            UserId = user.UserId, Username = "test.user", PasswordSalt = salt,
            PasswordHash = Rfc2898DeriveBytes.Pbkdf2("correct password", salt,
                LoginService.PasswordIterations, HashAlgorithmName.SHA256, 32)
        });
        var role = Role.Create("ClaimsSpecialist", "Claims specialist", DateTimeOffset.UtcNow);
        db.Roles.Add(role);
        db.RoleAssignments.Add(RoleAssignment.Create(
            user.UserId,
            role.RoleId,
            DateOnly.FromDateTime(DateTime.UtcNow.AddDays(-1)),
            null,
            "test",
            DateTimeOffset.UtcNow));
        await db.SaveChangesAsync();
        var controller = new LoginController(new LoginService(db, TimeProvider.System))
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() }
        };
        var result = await controller.Login(new LoginRequest { Username = username, Password = password }, default);
        var response = Assert.IsAssignableFrom<ObjectResult>(result.Result);
        Assert.Equal(success ? 200 : 401, response.StatusCode);
        var loginResponse = Assert.IsType<LoginResponse>(response.Value);
        Assert.Equal(success, loginResponse.Authenticated);
        if (success)
        {
            Assert.Equal("test@example.test", loginResponse.Email);
            Assert.Equal(["ClaimsSpecialist"], loginResponse.Roles);
        }
        else
        {
            Assert.Null(loginResponse.Email);
            Assert.Empty(loginResponse.Roles);
        }
        Assert.Equal("no-store", controller.Response.Headers.CacheControl.ToString());
    }

    [Fact]
    public async Task Login_endpoint_allows_anonymous_requests_through_custom_guard()
    {
        var context = new DefaultHttpContext();
        context.Request.Path = "/entitlement/v1/login";
        var attribute = typeof(LoginController).GetMethod(nameof(LoginController.Login))!
            .GetCustomAttributes(typeof(AllowAnonymousAttribute), false).Single();
        context.SetEndpoint(new Endpoint(_ => Task.CompletedTask, new EndpointMetadataCollection(attribute), "login"));
        var called = false;
        await new AuthenticatedUserMiddleware(_ => { called = true; return Task.CompletedTask; }).InvokeAsync(context);
        Assert.True(called);
    }
}
