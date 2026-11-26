using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;

namespace WorkflowPlatform.Api.Api;

public static class IdentityEndpoints
{
    public static void MapIdentityEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/me", async (ActorResolver actors, HttpContext context, SqlDatabase db, CancellationToken ct) =>
        {
            var actor = await actors.ResolveAsync(context.User, ct);
            var assignments = (await db.QueryAsync(@"
SELECT r.Code AS roleCode,r.Name AS roleName,r.Scope AS scope,a.ProjectId AS projectId,a.TeamId AS teamId
FROM auth.RoleAssignments a JOIN auth.Roles r ON r.RoleId=a.RoleId
WHERE a.UserId=@actor AND a.IsActive=1 AND r.IsActive=1",
                new[] { SqlDatabase.G("actor", actor.UserId) }, ct)).First;
            var email = await db.ScalarAsync("SELECT Email FROM auth.Users WHERE UserId=@actor", new[]{SqlDatabase.G("actor",actor.UserId)},ct);
            return Results.Ok(new { id = actor.UserId, username = actor.UserName, name = actor.DisplayName, email,
                platformAdmin = actor.PlatformAdmin, assignments });
        });
        api.MapGet("/users", async (HttpContext ctx, ActorResolver actors, ProjectAccess access,
            SqlDatabase db, long? projectId, string? q, int? take, CancellationToken ct) =>
        {
            var actor = await actors.ResolveAsync(ctx.User, ct);
            if (projectId is null) await access.RequireAdminAsync(actor, null, ct);
            else await access.RequireAdminAsync(actor, projectId, ct);
            var rows = (await db.QueryAsync(@"
SELECT TOP (@take) u.UserId AS id,u.UserName AS username,u.DisplayName AS name,u.Email,
 u.DirectoryStatus,u.IsActive,u.LastDirectorySyncAt,
 CAST(auth.fn_IsAdmin(u.UserId,NULL) AS bit) AS platformAdmin
FROM auth.Users u
WHERE (@projectId IS NULL OR (u.IsActive=1 AND u.DirectoryStatus NOT IN('Resigned','Disabled')))
AND (@q IS NULL OR u.DisplayName LIKE N'%'+@q+N'%' OR u.UserName LIKE N'%'+@q+N'%')
ORDER BY u.DisplayName", new[] { SqlDatabase.G("projectId",projectId),SqlDatabase.S("q",string.IsNullOrWhiteSpace(q)?null:q),
                new SqlArgument("take",Math.Clamp(take??50,1,100),System.Data.SqlDbType.Int) }, ct)).First;
            return Results.Ok(rows);
        });
        api.MapGet("/roles", async (HttpContext ctx, ActorResolver actors, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            var actor = await actors.ResolveAsync(ctx.User, ct);
            await access.RequireAdminAsync(actor, null, ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT r.RoleId AS id,r.Code,r.Name,r.Description,r.Scope,r.IsSystem,r.IsActive,
 (SELECT rp.PermissionCode FROM auth.RolePermissions rp WHERE rp.RoleId=r.RoleId FOR JSON PATH) AS PermissionsJson
FROM auth.Roles r ORDER BY r.Scope,r.Name", [], ct)).First);
        });
        api.MapGet("/projects/{projectId:long}/available-roles", async (long projectId, HttpContext ctx,
            ActorResolver actors, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User,ct),projectId,ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT r.RoleId AS id,r.Code,r.Name,r.Scope,r.Description,
 (SELECT rp.PermissionCode FROM auth.RolePermissions rp WHERE rp.RoleId=r.RoleId FOR JSON PATH) AS PermissionsJson
FROM auth.Roles r WHERE r.Scope IN('Project','Team') AND r.IsActive=1 ORDER BY r.Scope,r.Name",[],ct)).First);
        });
        api.MapGet("/permissions", async (HttpContext ctx, ActorResolver actors, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User, ct), null, ct);
            return Results.Ok((await db.QueryAsync("SELECT PermissionCode,PermissionGroup,DisplayName FROM auth.Permissions ORDER BY PermissionGroup,DisplayName", [], ct)).First);
        });
        // Platform-admin-only reconciliation of the local SQL user directory. No Entra credentials required.
        api.MapPost("/directory/sync", async(HttpContext ctx,ActorResolver actors,ProjectAccess access,
            SqlDatabase db,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await access.RequireAdminAsync(actor,null,ct);
            var result=await db.ProcedureAsync("auth.usp_ReconcileLocalDirectory",new[] {
                SqlDatabase.G("ActorUserId",actor.UserId)},ct);
            return Results.Ok(result.First.FirstOrDefault() ?? new Dictionary<string,object?>());
        });
    }
}
