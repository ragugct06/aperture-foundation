using Aperture.Entitlements.Api.Controllers;
using Aperture.Entitlements.Infrastructure.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;

namespace Aperture.Entitlements.Tests;

internal static class SessionTestSupport
{
    public static IDistributedCache NewCache() =>
        new MemoryDistributedCache(Options.Create(new MemoryDistributedCacheOptions()));

    public static SessionService NewSessionService(IDistributedCache? cache = null, TimeProvider? time = null) =>
        new(cache ?? NewCache(), Options.Create(new LoginSessionOptions()), time ?? TimeProvider.System);

    public static LoginAuthenticationResult Alice() =>
        new(Guid.NewGuid(), "Alice", "Example", "alice@example.test", ["ClaimsSpecialist", "Supervisor"]);
}

// APP-1417: sessions are created by foundation at login and resolved by consumers through the
// shared distributed cache, so two replicas (two service instances over one cache here) agree.
public sealed class SessionServiceTests
{
    [Fact]
    public async Task Session_created_by_one_instance_is_resolved_by_another_instance_sharing_the_cache()
    {
        var sharedCache = SessionTestSupport.NewCache();
        var replicaA = SessionTestSupport.NewSessionService(sharedCache);
        var replicaB = SessionTestSupport.NewSessionService(sharedCache);
        var alice = SessionTestSupport.Alice();

        var created = await replicaA.CreateAsync(alice, default);
        var resolved = await replicaB.GetAsync(created.SessionId, default);

        Assert.NotNull(resolved);
        Assert.Equal(alice.UserId, resolved.UserId);
        Assert.Equal("alice@example.test", resolved.Email);
        Assert.Equal(["ClaimsSpecialist", "Supervisor"], resolved.Roles);
        Assert.Equal(43, created.SessionId.Length);
    }

    [Fact]
    public async Task Session_is_not_resolved_from_a_different_cache()
    {
        // The pre-fix situation: state private to one replica. Kept as the negative control.
        var created = await SessionTestSupport.NewSessionService().CreateAsync(SessionTestSupport.Alice(), default);

        Assert.Null(await SessionTestSupport.NewSessionService().GetAsync(created.SessionId, default));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("short")]
    [InlineData("ent:session:*")]
    [InlineData("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA!")]
    public async Task Malformed_ids_are_rejected_without_touching_the_cache(string? sessionId)
    {
        var cache = new CountingCache(SessionTestSupport.NewCache());
        var sut = SessionTestSupport.NewSessionService(cache);

        Assert.Null(await sut.GetAsync(sessionId, default));
        await sut.RevokeAsync(sessionId, default);

        Assert.Equal(0, cache.Reads);
        Assert.Equal(0, cache.Removes);
    }

    [Fact]
    public async Task Revoked_session_is_gone()
    {
        var sut = SessionTestSupport.NewSessionService();
        var created = await sut.CreateAsync(SessionTestSupport.Alice(), default);

        await sut.RevokeAsync(created.SessionId, default);

        Assert.Null(await sut.GetAsync(created.SessionId, default));
    }

    [Fact]
    public async Task Session_expires_after_the_sliding_lifetime_without_activity()
    {
        var clock = new TestClock();
#pragma warning disable CS0618 // MemoryDistributedCacheOptions only exposes the legacy ISystemClock hook.
        var cache = new MemoryDistributedCache(
            Options.Create(new MemoryDistributedCacheOptions { Clock = new SystemClockAdapter(clock) }));
#pragma warning restore CS0618
        var sut = SessionTestSupport.NewSessionService(cache, clock);
        var created = await sut.CreateAsync(SessionTestSupport.Alice(), default);

        clock.Advance(TimeSpan.FromHours(7));
        Assert.NotNull(await sut.GetAsync(created.SessionId, default));

        clock.Advance(TimeSpan.FromHours(7));
        Assert.NotNull(await sut.GetAsync(created.SessionId, default));

        clock.Advance(TimeSpan.FromHours(9));
        Assert.Null(await sut.GetAsync(created.SessionId, default));
    }

    private sealed class SystemClockAdapter(TimeProvider provider) : Microsoft.Extensions.Internal.ISystemClock
    {
        public DateTimeOffset UtcNow => provider.GetUtcNow();
    }

    private sealed class TestClock : TimeProvider
    {
        private DateTimeOffset _now = new(2026, 10, 15, 12, 0, 0, TimeSpan.Zero);

        public override DateTimeOffset GetUtcNow() => _now;

        public void Advance(TimeSpan by) => _now = _now.Add(by);
    }

    private sealed class CountingCache(IDistributedCache inner) : IDistributedCache
    {
        public int Reads { get; private set; }
        public int Removes { get; private set; }

        public byte[]? Get(string key) { Reads++; return inner.Get(key); }
        public Task<byte[]?> GetAsync(string key, CancellationToken token = default) { Reads++; return inner.GetAsync(key, token); }
        public void Refresh(string key) => inner.Refresh(key);
        public Task RefreshAsync(string key, CancellationToken token = default) => inner.RefreshAsync(key, token);
        public void Remove(string key) { Removes++; inner.Remove(key); }
        public Task RemoveAsync(string key, CancellationToken token = default) { Removes++; return inner.RemoveAsync(key, token); }
        public void Set(string key, byte[] value, DistributedCacheEntryOptions options) => inner.Set(key, value, options);
        public Task SetAsync(string key, byte[] value, DistributedCacheEntryOptions options, CancellationToken token = default) => inner.SetAsync(key, value, options, token);
    }
}

public sealed class SessionControllerTests
{
    [Fact]
    public async Task Get_resolves_the_session_from_the_header()
    {
        var sessions = SessionTestSupport.NewSessionService();
        var created = await sessions.CreateAsync(SessionTestSupport.Alice(), default);
        var controller = NewController(sessions, context => context.Request.Headers[SessionService.HeaderName] = created.SessionId);

        var result = await controller.Get(default);

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        var body = Assert.IsType<SessionResponse>(ok.Value);
        Assert.True(body.Authenticated);
        Assert.Equal(created.SessionId, body.SessionId);
        Assert.Equal("alice@example.test", body.Email);
        Assert.Equal(["ClaimsSpecialist", "Supervisor"], body.Roles);
        Assert.Equal("no-store", controller.Response.Headers.CacheControl.ToString());
    }

    [Fact]
    public async Task Get_resolves_the_session_from_the_cookie_when_no_header_is_sent()
    {
        var sessions = SessionTestSupport.NewSessionService();
        var created = await sessions.CreateAsync(SessionTestSupport.Alice(), default);
        var controller = NewController(sessions, context => context.Request.Headers.Cookie = $"Aperture.Session={created.SessionId}");

        var result = await controller.Get(default);

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        Assert.Equal(created.SessionId, Assert.IsType<SessionResponse>(ok.Value).SessionId);
    }

    [Fact]
    public async Task Get_without_a_live_session_is_401()
    {
        var controller = NewController(SessionTestSupport.NewSessionService(), _ => { });

        var result = await controller.Get(default);

        var unauthorized = Assert.IsType<UnauthorizedObjectResult>(result.Result);
        var body = Assert.IsType<SessionResponse>(unauthorized.Value);
        Assert.False(body.Authenticated);
        Assert.Null(body.SessionId);
        Assert.Empty(body.Roles);
    }

    [Fact]
    public async Task End_revokes_the_session_and_clears_the_cookie()
    {
        var sessions = SessionTestSupport.NewSessionService();
        var created = await sessions.CreateAsync(SessionTestSupport.Alice(), default);
        var controller = NewController(sessions, context => context.Request.Headers[SessionService.HeaderName] = created.SessionId);

        var result = await controller.End(default);

        Assert.IsType<NoContentResult>(result);
        Assert.Null(await sessions.GetAsync(created.SessionId, default));
        Assert.Contains("Aperture.Session=;", controller.Response.Headers.SetCookie.ToString());
    }

    private static SessionController NewController(ISessionService sessions, Action<HttpContext> arrange)
    {
        var context = new DefaultHttpContext();
        arrange(context);
        return new SessionController(sessions, Options.Create(new LoginSessionOptions()))
        {
            ControllerContext = new ControllerContext { HttpContext = context }
        };
    }
}
