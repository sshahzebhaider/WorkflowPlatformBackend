using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;
using static WorkflowPlatform.Api.Api.ProcedureApi;
namespace WorkflowPlatform.Api.Api;

public static class PlatformEndpoints
{
    public static void MapPlatformEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/projects", async (HttpContext ctx, ActorResolver actors, SqlDatabase db, CancellationToken ct) =>
        {
            var a = await actors.ResolveAsync(ctx.User, ct);
            var rows = (await db.QueryAsync(@"
SELECT p.ProjectId AS id,p.Code AS code,p.Name AS name,p.Description AS description,p.OwnerUserId AS ownerUserId,
 p.CalendarId AS calendarId,p.DefaultSlaMinutes AS defaultSlaMinutes,p.Status AS status,
 p.RcaRequired AS rcaRequired,p.RcaEnabled AS rcaEnabled,p.RcaTemplateId AS rcaTemplateId,p.ReferencePrefix AS referencePrefix,
 p.TemplateCode AS templateCode,p.CreatedAt AS createdAt,
 p.Status AS releaseStage,
 CAST(0 AS INT) AS releaseRevision,
 CAST(1 AS INT) AS releaseCycle
FROM core.Projects p
WHERE auth.fn_IsAdmin(@actor,NULL)=1 OR EXISTS
 (SELECT 1 FROM auth.RoleAssignments ra WHERE ra.ProjectId=p.ProjectId AND ra.UserId=@actor AND ra.IsActive=1)
 OR EXISTS (SELECT 1 FROM teams.Teams tm JOIN teams.Members m ON m.TeamId=tm.TeamId
 WHERE tm.ProjectId=p.ProjectId AND m.UserId=@actor AND m.IsActive=1 AND tm.IsActive=1)
ORDER BY p.Name", new[] { SqlDatabase.G("actor", a.UserId) }, ct)).First;
            return Results.Ok(rows);
        });
        api.MapGet("/projects/{projectId:long}", async (long projectId, HttpContext ctx, ActorResolver actors,
            ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            var a = await actors.ResolveAsync(ctx.User, ct);
            await access.RequireAsync(a, projectId, "project.view", ct);
            var records = (await db.QueryAsync(@"
SELECT p.ProjectId AS id,p.Code,p.Name,p.Description,p.Status,p.OwnerUserId,p.CalendarId,
 p.DefaultSlaMinutes,p.ReferencePrefix,p.RcaRequired,p.RcaEnabled,p.RcaTemplateId,p.CreatedAt,p.UpdatedAt
FROM core.Projects p WHERE p.ProjectId=@id", new[] { SqlDatabase.G("id", projectId) }, ct)).First;
            if (records.Count == 0) return Results.NotFound();
            var terms = (await db.QueryAsync("SELECT TermKey,TermValue FROM core.ProjectTerminology WHERE ProjectId=@id",
                new[] { SqlDatabase.G("id", projectId) }, ct)).First;
            return Results.Ok(new { project = records[0], terminology = terms });
        });
        api.MapGet("/projects/{projectId:long}/permissions", async (long projectId, HttpContext ctx,
            ActorResolver actors, SqlDatabase db, CancellationToken ct) =>
        {
            var actor = await actors.ResolveAsync(ctx.User, ct);
            var rows = (await db.QueryAsync(@"
SELECT DISTINCT rp.PermissionCode FROM auth.RoleAssignments a
JOIN auth.Roles r ON r.RoleId=a.RoleId AND r.IsActive=1
JOIN auth.RolePermissions rp ON rp.RoleId=r.RoleId
WHERE a.UserId=@actor AND a.IsActive=1 AND (a.ProjectId=@project OR r.Scope='Platform' AND a.ProjectId IS NULL)",
            new[] { SqlDatabase.G("actor", actor.UserId), SqlDatabase.G("project", projectId) }, ct)).First;
            return Results.Ok(rows.Select(x => x["PermissionCode"]));
        });
        api.MapGet("/projects/{projectId:long}/terminology", async (long projectId, HttpContext ctx,
            ActorResolver actors, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User, ct), projectId, "project.view", ct);
            return Results.Ok((await db.QueryAsync("SELECT TermKey,TermValue FROM core.ProjectTerminology WHERE ProjectId=@id",
                new[] { SqlDatabase.G("id", projectId) }, ct)).First);
        });
        api.MapGet("/projects/{projectId:long}/role-assignments", async (long projectId, HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User,ct),projectId,ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT a.AssignmentId,a.UserId,u.UserName,u.DisplayName,r.RoleId,r.Code AS RoleCode,
 a.ProjectId,a.TeamId,a.IsActive,a.AssignedAt
FROM auth.RoleAssignments a JOIN auth.Roles r ON r.RoleId=a.RoleId
JOIN auth.Users u ON u.UserId=a.UserId
WHERE a.ProjectId=@project ORDER BY u.DisplayName,r.Code",
                new[] {SqlDatabase.G("project",projectId)},ct)).First);
        });
        api.MapGet("/projects/{projectId:long}/rca-fields", async (long projectId,HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct)=>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"cases.view",ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT FieldKey,ConfigJson,SortOrder FROM core.ProjectRcaFields WHERE ProjectId=@project ORDER BY SortOrder",
                new[] {SqlDatabase.G("project",projectId)},ct)).First);
        });
        api.MapGet("/audit", async (HttpContext ctx,ActorResolver actors,ProjectAccess access,
            SqlDatabase db,int? take,CancellationToken ct)=>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User,ct),null,ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT TOP (@take) AuditId,ProjectId,ActorUserId,EntityType,EntityId,ActionCode,DetailsJson,OccurredAt
FROM audit.Events ORDER BY AuditId DESC",
                new[] {new SqlArgument("take",Math.Clamp(take??100,1,200),System.Data.SqlDbType.Int)},ct)).First);
        });
        api.MapGet("/projects/{projectId:long}/audit", async(long projectId,HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,int? take,CancellationToken ct)=>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"audit.view",ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT TOP (@take) AuditId,ActorUserId,EntityType,EntityId,ActionCode,DetailsJson,OccurredAt
FROM audit.Events WHERE ProjectId=@project ORDER BY AuditId DESC",
                new[] {SqlDatabase.G("project",projectId),new SqlArgument("take",Math.Clamp(take??100,1,200),System.Data.SqlDbType.Int)},ct)).First);
        });
        // Server-side paginated audit history. Legacy /audit?take= endpoints remain available
        // for initial workspace loads and other existing clients.
        api.MapGet("/audit/paged", async (HttpContext ctx,ActorResolver actors,ProjectAccess access,
            SqlDatabase db,int? page,int? pageSize,CancellationToken ct)=>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User,ct),null,ct);
            var currentPage=Math.Clamp(page??1,1,1000000);
            var size=Math.Clamp(pageSize??15,1,100);
            var offset=(long)(currentPage-1)*size;
            var result=await db.QueryAsync(@"
SELECT e.AuditId,e.ProjectId,e.ActorUserId,u.DisplayName AS ActorName,
       e.EntityType,e.EntityId,e.ActionCode,e.DetailsJson,e.OccurredAt
FROM audit.Events e LEFT JOIN auth.Users u ON u.UserId=e.ActorUserId
ORDER BY e.AuditId DESC
OFFSET @offset ROWS FETCH NEXT @size ROWS ONLY;
SELECT COUNT_BIG(*) AS Total FROM audit.Events;",
                new[]{SqlDatabase.G("offset",offset),new SqlArgument("size",size,System.Data.SqlDbType.Int)},ct);
            var total=result.Sets.Count>1&&result.Sets[1].Count>0
                ? Convert.ToInt64(result.Sets[1][0]["Total"]) : 0L;
            return Results.Ok(new{rows=result.First,total,page=currentPage,pageSize=size});
        });
        api.MapGet("/projects/{projectId:long}/audit/paged", async(long projectId,HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,int? page,int? pageSize,CancellationToken ct)=>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"audit.view",ct);
            var currentPage=Math.Clamp(page??1,1,1000000);
            var size=Math.Clamp(pageSize??15,1,100);
            var offset=(long)(currentPage-1)*size;
            var result=await db.QueryAsync(@"
SELECT e.AuditId,e.ProjectId,e.ActorUserId,u.DisplayName AS ActorName,
       e.EntityType,e.EntityId,e.ActionCode,e.DetailsJson,e.OccurredAt
FROM audit.Events e LEFT JOIN auth.Users u ON u.UserId=e.ActorUserId
WHERE e.ProjectId=@project
ORDER BY e.AuditId DESC
OFFSET @offset ROWS FETCH NEXT @size ROWS ONLY;
SELECT COUNT_BIG(*) AS Total FROM audit.Events WHERE ProjectId=@project;",
                new[]{SqlDatabase.G("project",projectId),SqlDatabase.G("offset",offset),
                    new SqlArgument("size",size,System.Data.SqlDbType.Int)},ct);
            var total=result.Sets.Count>1&&result.Sets[1].Count>0
                ? Convert.ToInt64(result.Sets[1][0]["Total"]) : 0L;
            return Results.Ok(new{rows=result.First,total,page=currentPage,pageSize=size});
        });
        api.MapProc("/projects/onboard", "core.usp_OnboardProject", "platformAdmin",
            S("Name",true),S("Code"),G("OwnerUserId",false),G("CalendarId"), J("AdminIdsJson"), J("TermsJson",false),J("TeamsJson",false),
            S("Description"),S("TemplateCode"),G("RcaTemplateId",false),B("RcaRequired"),I("DefaultSlaMinutes"),O("ProjectId"));
        api.MapProc("/projects/{projectId:long}/terminology", "core.usp_SetTerminology", "admin",G("ProjectId"),J("TermsJson"));
        api.MapProc("/projects/{projectId:long}/calendar", "core.usp_SetProjectCalendar", "admin",
            G("ProjectId"),G("CalendarId"),I("SlaMinutes",true));
        api.MapProc("/projects/{projectId:long}/rca-fields", "core.usp_SetProjectRcaFields", "admin", G("ProjectId"),J("FieldsJson"));
        api.MapProc("/projects/{projectId:long}/rca-config", "core.usp_SaveProjectRcaConfig", "admin",
            G("ProjectId"),B("Enabled",true),B("RequiredOnClose",true),G("TemplateId",false),J("FieldsJson"));
        api.MapProc("/projects/{projectId:long}/allow-data-source", "core.usp_AllowProjectDataSource", "admin",G("ProjectId"),G("DataSourceId"),B("Allowed",true));
        api.MapProc("/projects/{projectId:long}/allow-lookup", "core.usp_AllowProjectLookup", "admin",G("ProjectId"),G("ListId"),B("Allowed",true));

        api.MapGet("/calendars", async (HttpContext ctx, ActorResolver actors, ProjectAccess access,
            SqlDatabase db, CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User, ct), null, ct);
            var results = await db.QueryAsync("SELECT CalendarId AS id,Code,Name,TimeZoneId,Description,IsActive FROM calendar.Calendars ORDER BY Name", [], ct);
            return Results.Ok(results.First);
        });
        api.MapGet("/calendars/{calendarId:long}", async (long calendarId, HttpContext ctx,
            ActorResolver actors, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User, ct), null, ct);
            var args = new[] { SqlDatabase.G("id",calendarId) };
            var result = await db.QueryAsync("SELECT CalendarId AS id,Code,Name,TimeZoneId,Description,IsActive FROM calendar.Calendars WHERE CalendarId=@id; SELECT DayOfWeek,StartMinute,EndMinute FROM calendar.WorkingIntervals WHERE CalendarId=@id ORDER BY DayOfWeek,StartMinute; SELECT HolidayId,Name,StartDate,EndDate FROM calendar.Holidays WHERE CalendarId=@id ORDER BY StartDate", args, ct);
            if (result.First.Count == 0) return Results.NotFound();
            return Results.Ok(new { calendar = result.First[0], intervals = result.Sets[1], holidays = result.Sets[2] });
        });
        api.MapProc("/calendars", "calendar.usp_CreateCalendar", "platformAdmin",S("Code"),S("Name",true),S("TimeZoneId"),O("CalendarId"));
        api.MapProc("/calendars/{calendarId:long}/intervals", "calendar.usp_SetWorkingInterval", "platformAdmin",
            G("CalendarId"),I("DayOfWeek",true),I("StartMinute",true),I("EndMinute",true));
        api.MapProc("/calendars/{calendarId:long}/holidays", "calendar.usp_AddHolidayRange", "platformAdmin",
            G("CalendarId"),S("Name",true),D("StartDate"),D("EndDate"),O("HolidayId"));
        api.MapProc("/calendars/holidays/{holidayId:long}/remove", "calendar.usp_RemoveHolidayDate", "platformAdmin",
            G("HolidayId"),D("DateToRemove",false));
        api.MapProc("/roles", "auth.usp_SaveCustomRole", "platformAdmin",S("Name",true),S("Code"),S("Scope"),J("PermissionsJson"),O("RoleId"),S("Description"));
        api.MapProc("/roles/assign", "auth.usp_AssignRole", "admin", G("UserId"),S("RoleCode",true),G("ProjectId",false),G("TeamId",false));
        api.MapProc("/directory/create-platform-admin", "auth.usp_CreatePlatformAdminUser", "platformAdmin",
            S("UserName",true),S("DisplayName",true),S("Email"),O("UserId"));
        api.MapProc("/directory/upsert", "auth.usp_UpsertDirectoryUser", "platformAdmin",
            S("UserName",true),S("DisplayName",true),S("Email"),S("ExternalDirectoryId"),S("DirectoryStatus"),S("Mobile"),O("UserId"));
        api.MapProc("/directory/resigned", "teams.usp_ApplyResignedUser", "platformAdmin",G("UserId"));
        api.MapProc("/directory/{userId:long}/status", "auth.usp_SetDirectoryStatus", "platformAdmin",G("UserId"),S("DirectoryStatus",true));
        api.MapProc("/rca-templates", "core.usp_SaveRcaTemplate", "platformAdmin",
            S("Name",true),S("Code"),J("FieldsJson"),O("RcaTemplateId"));
        api.MapGet("/rca-templates", async (HttpContext ctx, ActorResolver actors, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User, ct), null, ct);
            return Results.Ok((await db.QueryAsync("SELECT RcaTemplateId AS id,Code,Name,Description,Version,IsActive FROM core.RcaTemplates ORDER BY Name", [], ct)).First);
        });
        api.MapGet("/rca-templates/{id:long}/fields", async (long id, HttpContext ctx, ActorResolver actors, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User, ct), null, ct);
            return Results.Ok((await db.QueryAsync("SELECT RcaFieldId,FieldKey,Label,Description,FieldType,Required,ParentFieldKey,ParentValue,OptionsJson,SortOrder FROM core.RcaTemplateFields WHERE RcaTemplateId=@id ORDER BY SortOrder", new[] { SqlDatabase.G("id",id) }, ct)).First);
        });
    }
}
