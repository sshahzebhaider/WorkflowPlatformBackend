using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;

namespace WorkflowPlatform.Api.Api;

/// <summary>
/// Read-only views needed to render the existing JSX screens without granting project members
/// access to the platform-wide user directory or unpublished documents.
/// All reads are scoped by the SQL authenticated actor and the specified project.
/// </summary>
public static class FrontendReadEndpoints
{
    public static void MapFrontendReadEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/projects/{projectId:long}/directory", async (long projectId, HttpContext ctx,
            ActorResolver resolver, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            var actor = await resolver.ResolveAsync(ctx.User, ct);
            await access.RequireAsync(actor, projectId, "project.view", ct);
            var rows = (await db.QueryAsync(@"
SELECT DISTINCT u.UserId AS id, u.UserName AS username, u.DisplayName AS name,
 CASE WHEN u.UserId=@actor OR auth.fn_IsAdmin(@actor,@project)=1 THEN u.Email ELSE NULL END AS email,
 u.DirectoryStatus AS directoryStatus, u.IsActive AS active,
 CAST(auth.fn_IsAdmin(u.UserId,NULL) AS bit) AS platformAdmin
FROM auth.Users u
WHERE u.IsActive=1 AND u.DirectoryStatus NOT IN('Resigned','Disabled') AND (
 u.UserId=@actor OR EXISTS (SELECT 1 FROM teams.Members m JOIN teams.Teams t ON t.TeamId=m.TeamId
 WHERE t.ProjectId=@project AND m.UserId=u.UserId AND m.IsActive=1 AND t.IsActive=1)
 OR EXISTS (SELECT 1 FROM auth.RoleAssignments ra
 WHERE ra.ProjectId=@project AND ra.UserId=u.UserId AND ra.IsActive=1))
ORDER BY name",new[]{SqlDatabase.G("actor",actor.UserId),SqlDatabase.G("project",projectId)},ct)).First;
            return Results.Ok(rows);
        });

        // A project administrator must be able to choose an existing calendar without
        // receiving permission to change platform-wide calendars.
        api.MapGet("/projects/{projectId:long}/available-calendars", async(long projectId,
            HttpContext ctx,ActorResolver resolver,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await resolver.ResolveAsync(ctx.User,ct),projectId,ct);
            var rows=(await db.QueryAsync(@"SELECT CalendarId AS id, Code, Name,TimeZoneId,Description,IsActive
                FROM calendar.Calendars WHERE IsActive=1 ORDER BY Name",[],ct)).First;
            return Results.Ok(rows);
        });

        api.MapGet("/projects/{projectId:long}/lookups/{listId:long}/items", async(long projectId,long listId,
            HttpContext ctx,ActorResolver resolver,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAsync(await resolver.ResolveAsync(ctx.User,ct),projectId,"project.view",ct);
            var rows=(await db.QueryAsync(@"
SELECT i.ItemId AS id,i.Code AS code,i.Label AS label,i.ParentItemId AS parentItemId,
 i.SortOrder AS sortOrder,i.IsActive AS active,
 (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),lp.ParentItemId),N',') FROM lookup.ItemParents lp WHERE lp.ItemId=i.ItemId) AS parentItemIdsCsv
FROM lookup.Items i JOIN lookup.Lists l ON l.ListId=i.ListId
WHERE i.ListId=@list AND l.IsActive=1 AND (l.ProjectId=@project OR
 (l.Scope='Global' AND EXISTS (SELECT 1 FROM lookup.ProjectLists pl
  WHERE pl.ProjectId=@project AND pl.ListId=l.ListId)))
ORDER BY i.SortOrder,i.Label",new[]{SqlDatabase.G("list",listId),SqlDatabase.G("project",projectId)},ct)).First;
            return Results.Ok(rows);
        });

        // The case-details stored procedure is the authorization gate. Never query these
        // published snapshots without checking case membership first.
        api.MapGet("/projects/{projectId:long}/cases/{caseId:long}/ui-context", async(long projectId,long caseId,
            HttpContext ctx,ActorResolver resolver,SqlDatabase db,CancellationToken ct) =>
        {
            var actor=await resolver.ResolveAsync(ctx.User,ct);
            var args=new[]{SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("ProjectId",projectId),SqlDatabase.G("CaseId",caseId)};
            await db.ProcedureAsync("work.usp_GetCaseDetails",args,ct);
            var rows=await db.QueryAsync(@"
SELECT ct.CaseTypeId AS caseTypeId,ct.Name AS caseTypeName,ctv.VersionNumber AS caseTypeVersion,
 ctv.PublishedConfigJson AS caseTypeConfigJson,fv.FormId AS intakeFormId,fd.Name AS intakeFormName,
 fv.FormVersionId AS intakeFormVersionId,fv.VersionNumber AS intakeFormVersion,
 fv.DefinitionJson AS intakeDefinitionJson,wv.WorkflowVersionId AS workflowVersionId,
 wv.VersionNumber AS workflowVersion,wv.GraphJson AS workflowGraphJson
FROM work.Cases c
JOIN core.CaseTypeVersions ctv ON ctv.CaseTypeVersionId=c.CaseTypeVersionId
JOIN core.CaseTypes ct ON ct.CaseTypeId=ctv.CaseTypeId
JOIN forms.Versions fv ON fv.FormVersionId=ctv.IntakeFormVersionId
JOIN forms.Definitions fd ON fd.FormId=fv.FormId
JOIN flow.Versions wv ON wv.WorkflowVersionId=c.WorkflowVersionId
WHERE c.CaseId=@case AND c.ProjectId=@project;
SELECT n.NodeKey AS nodeKey,nf.FormVersionId AS formVersionId,fv.FormId AS formId,
 fd.Name AS name,fv.DefinitionJson AS definitionJson
FROM work.Cases c JOIN flow.Nodes n ON n.WorkflowVersionId=c.WorkflowVersionId
JOIN flow.NodeForms nf ON nf.NodeId=n.NodeId
JOIN forms.Versions fv ON fv.FormVersionId=nf.FormVersionId
JOIN forms.Definitions fd ON fd.FormId=fv.FormId
WHERE c.CaseId=@case AND c.ProjectId=@project;
SELECT n.NodeId AS nodeId,n.NodeKey AS nodeKey FROM flow.Nodes n JOIN work.Cases c ON c.WorkflowVersionId=n.WorkflowVersionId
WHERE c.CaseId=@case AND c.ProjectId=@project",
                new[]{SqlDatabase.G("case",caseId),SqlDatabase.G("project",projectId)},ct);
            return Results.Ok(new { published = rows.First.FirstOrDefault(), stepForms=rows.Sets.ElementAtOrDefault(1)??new(),nodes=rows.Sets.ElementAtOrDefault(2)??new() });
        });

        // Case type drafts are real persisted drafts, never a browser-only edit.
        api.MapPost("/case-types/{caseTypeId:long}/draft", async(long caseTypeId,HttpContext ctx,
            ActorResolver resolver,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            var actor=await resolver.ResolveAsync(ctx.User,ct);
            var matches=(await db.QueryAsync("SELECT ProjectId FROM core.CaseTypes WHERE CaseTypeId=@id",
                new[]{SqlDatabase.G("id",caseTypeId)},ct)).First;
            if(matches.Count==0)return Results.NotFound();
            var projectId=(long)matches[0]["ProjectId"]!;
            await access.RequireAdminAsync(actor,projectId,ct);
            using var body=await System.Text.Json.JsonDocument.ParseAsync(ctx.Request.Body,cancellationToken:ct);
            if(body.RootElement.ValueKind!=System.Text.Json.JsonValueKind.Object)
                throw new ArgumentException("Draft must be a JSON object.");
            var data=body.RootElement;
            var name=data.TryGetProperty("name",out var n)&&n.ValueKind==System.Text.Json.JsonValueKind.String?n.GetString():null;
            if(string.IsNullOrWhiteSpace(name))throw new ArgumentException("Case type name is required.");
            await db.ProcedureAsync("core.usp_SaveCaseTypeDraft", new[]{
                SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("CaseTypeId",caseTypeId),
                SqlDatabase.S("Name",name),SqlDatabase.S("DraftJson",data.GetRawText())},ct);
            return Results.Ok(new {caseTypeId,status="Draft saved"});
        });

        api.MapPost("/projects/{projectId:long}/teams/{teamId:long}/details", async(long projectId,long teamId,
            HttpContext ctx,ActorResolver resolver,ProjectAccess access,SqlDatabase db,CancellationToken ct)=>
        {
            var actor=await resolver.ResolveAsync(ctx.User,ct);
            await access.RequireAdminAsync(actor,projectId,ct);
            using var doc=await System.Text.Json.JsonDocument.ParseAsync(ctx.Request.Body,cancellationToken:ct);
            var row=doc.RootElement;
            var name=row.GetProperty("name").GetString();
            var description=row.TryGetProperty("description",out var d)?d.GetString():null;
            if(string.IsNullOrWhiteSpace(name))throw new ArgumentException("Team name required.");
            await db.ProcedureAsync("teams.usp_UpdateTeamDetails",new[]{
                SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("ProjectId",projectId),
                SqlDatabase.G("TeamId",teamId),SqlDatabase.S("Name",name),
                SqlDatabase.S("Description",description)},ct);
            return Results.Ok(new{teamId});
        });

        api.MapPost("/calendars/{calendarId:long}/details", async(long calendarId,HttpContext ctx,
            ActorResolver resolver,ProjectAccess access,SqlDatabase db,CancellationToken ct)=>
        {
            var actor=await resolver.ResolveAsync(ctx.User,ct);
            await access.RequireAdminAsync(actor,null,ct);
            using var doc=await System.Text.Json.JsonDocument.ParseAsync(ctx.Request.Body,cancellationToken:ct);
            var row=doc.RootElement;
            var name=row.GetProperty("name").GetString();
            var timezone=row.GetProperty("timezone").GetString();
            if(string.IsNullOrWhiteSpace(name)||string.IsNullOrWhiteSpace(timezone))
                throw new ArgumentException("Calendar name and timezone required.");
            await db.ProcedureAsync("calendar.usp_UpdateCalendarDetails",new[]{
                SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("CalendarId",calendarId),
                SqlDatabase.S("Name",name),SqlDatabase.S("TimeZoneId",timezone)},ct);
            return Results.Ok(new {calendarId});
        });
        api.MapPost("/calendars/{calendarId:long}/schedule", async(long calendarId,HttpContext ctx,
            ActorResolver resolver,ProjectAccess access,SqlDatabase db,CancellationToken ct)=>
        {
            var actor=await resolver.ResolveAsync(ctx.User,ct);
            await access.RequireAdminAsync(actor,null,ct);
            using var doc=await System.Text.Json.JsonDocument.ParseAsync(ctx.Request.Body,cancellationToken:ct);
            var json=doc.RootElement.GetRawText();
            await db.ProcedureAsync("calendar.usp_ReplaceSchedule",new[]{
                SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("CalendarId",calendarId),
                SqlDatabase.S("ScheduleJson",json)},ct);
            return Results.Ok(new {calendarId});
        });
    }
}
