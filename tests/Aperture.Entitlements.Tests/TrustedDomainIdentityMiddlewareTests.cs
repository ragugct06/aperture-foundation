using Aperture.Entitlements.Api.Middleware;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace Aperture.Entitlements.Tests;

public sealed class TrustedDomainIdentityMiddlewareTests
{
    [Fact]
    public async Task Verified_headers_create_an_authenticated_principal()
    {
        var context = new DefaultHttpContext();
        context.Request.Headers["X-Aperture-Identity-Verified"] = "true";
        context.Request.Headers["X-Aperture-User-Email"] = "admin@example.test";
        var called = false;
        var sut = new TrustedDomainIdentityMiddleware(
            _ =>
            {
                called = true;
                return Task.CompletedTask;
            },
            Options.Create(new TrustedDomainIdentityOptions()),
            NullLogger<TrustedDomainIdentityMiddleware>.Instance);

        await sut.InvokeAsync(context);

        Assert.True(called);
        Assert.True(context.User.Identity?.IsAuthenticated == true);
        Assert.Equal("admin@example.test", context.User.FindFirst("preferred_username")?.Value);
    }

    [Fact]
    public async Task Missing_verified_marker_does_not_create_a_principal()
    {
        var context = new DefaultHttpContext();
        context.Request.Headers["X-Aperture-User-Email"] = "spoofed@example.test";
        var sut = new TrustedDomainIdentityMiddleware(
            _ => Task.CompletedTask,
            Options.Create(new TrustedDomainIdentityOptions()),
            NullLogger<TrustedDomainIdentityMiddleware>.Instance);

        await sut.InvokeAsync(context);

        Assert.False(context.User.Identity?.IsAuthenticated ?? false);
    }

    [Fact]
    public async Task Verified_marker_without_email_does_not_create_a_principal()
    {
        var context = new DefaultHttpContext();
        context.Request.Headers["X-Aperture-Identity-Verified"] = "true";
        var sut = new TrustedDomainIdentityMiddleware(
            _ => Task.CompletedTask,
            Options.Create(new TrustedDomainIdentityOptions()),
            NullLogger<TrustedDomainIdentityMiddleware>.Instance);

        await sut.InvokeAsync(context);

        Assert.False(context.User.Identity?.IsAuthenticated ?? false);
    }

    [Fact]
    public async Task Authenticated_user_middleware_returns_401_for_anonymous_api_request()
    {
        var context = new DefaultHttpContext();
        context.Request.Path = "/api/users";
        context.Response.Body = new MemoryStream();
        var nextCalled = false;
        var sut = new AuthenticatedUserMiddleware(_ =>
        {
            nextCalled = true;
            return Task.CompletedTask;
        });

        await sut.InvokeAsync(context);

        Assert.False(nextCalled);
        Assert.Equal(StatusCodes.Status401Unauthorized, context.Response.StatusCode);
    }

    [Fact]
    public async Task Authenticated_user_middleware_allows_authenticated_api_request()
    {
        var context = new DefaultHttpContext
        {
            User = new System.Security.Claims.ClaimsPrincipal(
                new System.Security.Claims.ClaimsIdentity(
                    [new System.Security.Claims.Claim("preferred_username", "user@example.test")],
                    "TrustedDomainApi"))
        };
        context.Request.Path = "/api/users";
        var nextCalled = false;
        var sut = new AuthenticatedUserMiddleware(_ =>
        {
            nextCalled = true;
            return Task.CompletedTask;
        });

        await sut.InvokeAsync(context);

        Assert.True(nextCalled);
    }

    [Theory]
    [InlineData("/health")]
    [InlineData("/swagger/index.html")]
    public async Task Authenticated_user_middleware_allows_public_infrastructure_paths(string path)
    {
        var context = new DefaultHttpContext();
        context.Request.Path = path;
        var nextCalled = false;
        var sut = new AuthenticatedUserMiddleware(_ =>
        {
            nextCalled = true;
            return Task.CompletedTask;
        });

        await sut.InvokeAsync(context);

        Assert.True(nextCalled);
    }
}
