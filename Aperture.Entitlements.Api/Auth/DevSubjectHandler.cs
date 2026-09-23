// DEV ONLY — attaches X-Demo-Subject to every outbound request made by the
// typed Patient Identity SDK client so the identity service's dev auth gate
// accepts service-to-service calls without a real bearer token.
// Registered only when DevAuth:Enabled is true (Development environment).
// Production replaces this with an OAuth M2M client-credentials handler.

namespace Aperture.Entitlements.Api.Auth;

public sealed class DevSubjectHandler : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken ct)
    {
        request.Headers.TryAddWithoutValidation("X-Demo-Subject", "copay-service");
        return base.SendAsync(request, ct);
    }
}
