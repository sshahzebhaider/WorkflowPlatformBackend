using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Options;
using WorkflowPlatform.Api.Data;

namespace WorkflowPlatform.Api.Security;

public sealed class DevHeaderHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder,
    IWebHostEnvironment environment, IConfiguration configuration)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!environment.IsDevelopment() || !configuration.GetValue<bool>("Authentication:EnableDevHeaderAuth"))
            return Task.FromResult(AuthenticateResult.NoResult());
        var remote = Context.Connection.RemoteIpAddress;
        if (remote is null || !System.Net.IPAddress.IsLoopback(remote))
            return Task.FromResult(AuthenticateResult.Fail("Development identity headers require a loopback client."));
        if (!Request.Headers.TryGetValue("X-Dev-User", out var user) || string.IsNullOrWhiteSpace(user))
            return Task.FromResult(AuthenticateResult.NoResult());
        var claims = new[] { new Claim("dev_username", user.ToString()), new Claim(ClaimTypes.Name, user.ToString()) };
        var identity = new ClaimsIdentity(claims, Scheme.Name);
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name)));
    }
}

public sealed record Actor(long UserId, string UserName, string DisplayName, bool PlatformAdmin);

public sealed class ActorResolver(SqlDatabase db)
{
    public async Task<Actor> ResolveAsync(ClaimsPrincipal principal, CancellationToken ct)
    {
        var dev = principal.Identity?.AuthenticationType == "DevHeader" ? principal.FindFirst("dev_username")?.Value : null;
        var externalId = principal.FindFirst("oid")?.Value ?? principal.FindFirst("sub")?.Value;
        if (string.IsNullOrWhiteSpace(dev) && string.IsNullOrWhiteSpace(externalId))
            throw new UnauthorizedAccessException("No recognized identity claim.");
        var rows = (await db.QueryAsync(@"
SELECT TOP(1) u.UserId,u.UserName,u.DisplayName,
 CAST(auth.fn_IsAdmin(u.UserId,NULL) AS BIT) AS PlatformAdmin
FROM auth.Users u
WHERE u.IsActive=1 AND u.DirectoryStatus NOT IN('Resigned','Disabled')
 AND ((@dev IS NOT NULL AND u.UserName=@dev) OR (@dev IS NULL AND u.ExternalDirectoryId=@externalId))",
            new[] { SqlDatabase.S("dev", dev), SqlDatabase.S("externalId", dev is null ? externalId : null) }, ct)).First;
        if (rows.Count == 0) throw new UnauthorizedAccessException("Identity has not been provisioned or is inactive.");
        var u = rows[0];
        return new Actor((long)u["UserId"]!, (string)u["UserName"]!, (string)u["DisplayName"]!, Convert.ToBoolean(u["PlatformAdmin"]));
    }
}

public sealed class ProjectAccess(SqlDatabase db)
{
    public async Task RequireAsync(Actor actor, long? projectId, string permission, CancellationToken ct)
    {
        var result = await db.ScalarAsync("SELECT auth.fn_HasPermission(@actor,@project,@permission)",
            new[] { SqlDatabase.G("actor", actor.UserId), SqlDatabase.G("project", projectId), SqlDatabase.S("permission", permission) }, ct);
        if (result is null || !Convert.ToBoolean(result)) throw new AccessDeniedException();
    }
    public async Task RequireAdminAsync(Actor actor, long? projectId, CancellationToken ct)
    {
        var result = await db.ScalarAsync("SELECT auth.fn_IsAdmin(@actor,@project)",
            new[] { SqlDatabase.G("actor", actor.UserId), SqlDatabase.G("project", projectId) }, ct);
        if (result is null || !Convert.ToBoolean(result)) throw new AccessDeniedException();
    }
}
public sealed class AccessDeniedException : Exception { public AccessDeniedException() : base("Insufficient permissions for this action.") { } }
