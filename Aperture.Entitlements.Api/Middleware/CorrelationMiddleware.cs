namespace Aperture.Entitlements.Api.Middleware;

public sealed class CorrelationMiddleware(RequestDelegate next)
{
    public const string HeaderName = "X-Correlation-ID";

    public async Task InvokeAsync(HttpContext context)
    {
        var supplied = context.Request.Headers[HeaderName].ToString();
        var correlationId = Guid.TryParse(supplied, out var parsed)
            ? parsed.ToString()
            : Guid.NewGuid().ToString();
        context.Request.Headers[HeaderName] = correlationId;
        context.Response.Headers[HeaderName] = correlationId;
        await next(context);
    }
}
