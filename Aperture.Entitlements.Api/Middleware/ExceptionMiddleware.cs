using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Aperture.Entitlements.Api.Middleware;

public sealed class ExceptionMiddleware(RequestDelegate next, ILogger<ExceptionMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (UnauthorizedAccessException exception)
        {
            await WriteAsync(context, 401, "Authentication context unavailable", exception.Message);
        }
        catch (KeyNotFoundException exception)
        {
            await WriteAsync(context, 404, "Resource not found", exception.Message);
        }
        catch (ArgumentException exception)
        {
            await WriteAsync(context, 400, "Invalid request", exception.Message);
        }
        catch (DbUpdateException exception)
        {
            logger.LogWarning(exception, "A conflicting entitlement change was rejected.");
            await WriteAsync(context, 409, "Entitlement conflict", "The requested change conflicts with existing data.");
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Unhandled error while processing an entitlement request.");
            await WriteAsync(
                context,
                500,
                "Unexpected server error",
                "The request could not be completed. Use the correlation id when contacting support.");
        }
    }

    private static Task WriteAsync(HttpContext context, int status, string title, string detail)
    {
        context.Response.StatusCode = status;
        return context.Response.WriteAsJsonAsync(new ProblemDetails
        {
            Status = status,
            Title = title,
            Detail = detail
        });
    }
}
