using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;
using static WorkflowPlatform.Api.Api.ProcedureApi;

namespace WorkflowPlatform.Api.Api;

public static class ConfigurationEndpoints
{
    public static void MapConfigurationEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/projects/{projectId:long}/teams", async (long projectId, HttpContext ctx, ActorResolver actors, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User, ct), projectId, "teams.view", ct);
            var result = await db.QueryAsync(@"
SELECT TeamId AS id,Code,Name,Description,IsActive FROM teams.Teams WHERE ProjectId=@id ORDER BY Name;
SELECT m.TeamId,m.UserId,u.UserName,u.DisplayName,m.TeamRole,m.IsActive
FROM teams.Members m JOIN teams.Teams t ON t.TeamId=m.TeamId JOIN auth.Users u ON u.UserId=m.UserId
WHERE t.ProjectId=@id ORDER BY t.Name,m.TeamRole,u.DisplayName;
SELECT a.AbsenceId,a.TeamId,a.UserId,a.BackupUserId,a.StartDate,a.EndDate,a.IsActive
FROM teams.Absences a WHERE a.ProjectId=@id ORDER BY a.StartDate DESC", new[] { SqlDatabase.G("id",projectId) }, ct);
            return Results.Ok(new { teams = result.Sets[0], members = result.Sets[1], absences = result.Sets[2] });
        });
        api.MapProc("/projects/{projectId:long}/teams", "teams.usp_CreateTeam", "admin",
            G("ProjectId"), S("Code"), S("Name", true), O("TeamId"));
        api.MapProc("/projects/{projectId:long}/teams/{teamId:long}/members", "teams.usp_SetMember", "admin",
            G("ProjectId"), G("TeamId"), G("UserId"), S("TeamRole",true), B("IsActive"));
        api.MapProc("/projects/{projectId:long}/teams/{teamId:long}/absence", "teams.usp_SetLeaveBackup", null,
            G("ProjectId"),G("TeamId"),G("UserId"),G("BackupUserId"),D("StartDate"),D("EndDate"));

        api.MapGet("/projects/{projectId:long}/lookups", async (long projectId, HttpContext ctx, ActorResolver actors,
            ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User, ct), projectId,"project.view",ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT l.ListId AS id,l.ProjectId,l.Scope,l.ParentListId,l.Code,l.Name,l.IsActive,
(SELECT COUNT(*) FROM lookup.Items i WHERE i.ListId=l.ListId) AS itemCount
FROM lookup.Lists l WHERE l.IsActive=1 AND (l.ProjectId=@id OR l.Scope='Global'
AND EXISTS(SELECT 1 FROM lookup.ProjectLists pl WHERE pl.ProjectId=@id AND pl.ListId=l.ListId))
ORDER BY l.Name", new[] { SqlDatabase.G("id",projectId) }, ct)).First);
        });
        api.MapGet("/lookups", async (HttpContext ctx, ActorResolver actors, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User,ct),null,ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT l.ListId AS id,l.ProjectId,l.Scope,l.ParentListId,l.Code,l.Name,l.IsActive,
(SELECT COUNT(*) FROM lookup.Items i WHERE i.ListId=l.ListId) AS itemCount
FROM lookup.Lists l ORDER BY l.Name",[],ct)).First);
        });
        api.MapGet("/projects/{projectId:long}/lookups/{listId:long}/options", async (long projectId, long listId,
            long? parentItemId,HttpContext ctx, ActorResolver actors, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"project.view",ct);
            var result = await db.ProcedureAsync("lookup.usp_GetOptions",new[] {SqlDatabase.G("ProjectId",projectId),
                SqlDatabase.G("ListId",listId),SqlDatabase.G("ParentItemId",parentItemId)},ct);
            return Results.Ok(result.First);
        });
        api.MapGet("/lookups/{listId:long}/items", async (long listId, HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User,ct),null,ct);
            return Results.Ok((await db.QueryAsync(@"SELECT i.ItemId AS id,i.Code,i.Label,i.ParentItemId,i.SortOrder,i.IsActive,i.MetadataJson,
  (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),lp.ParentItemId),N',') FROM lookup.ItemParents lp WHERE lp.ItemId=i.ItemId) AS ParentItemIdsCsv
FROM lookup.Items i WHERE i.ListId=@id ORDER BY i.SortOrder,i.Label",
                new[] { SqlDatabase.G("id",listId) },ct)).First);
        });
        api.MapProc("/lookups", "lookup.usp_CreateList", null,
            S("Name",true),S("Code"),S("Scope",true),G("ProjectId",false),G("ParentListId",false),O("ListId"));
        api.MapProc("/lookups/create-with-items", "lookup.usp_CreateListWithItems", null,
            S("Name",true),S("Code"),S("Scope",true),G("ProjectId",false),G("ParentListId",false),
            J("ItemsJson"),J("LinksJson"),O("ListId"));
        api.MapProc("/lookups/{listId:long}/parent", "lookup.usp_SetParentList", null,G("ListId"),G("ParentListId",false));
        api.MapProc("/lookups/{listId:long}/items/bulk", "lookup.usp_BulkAddItems", null,G("ListId"),J("ItemsJson"));
        api.MapProc("/lookups/{listId:long}/item-parents", "lookup.usp_SetItemParentLinks", null,G("ListId"),J("LinksJson"));
        api.MapProc("/lookups/items/{itemId:long}", "lookup.usp_UpdateItem", null,
            G("ItemId"),S("Label",true),I("SortOrder",true),B("IsActive",true),G("ParentItemId",false));

        api.MapGet("/projects/{projectId:long}/field-library", async (long projectId,HttpContext ctx,ActorResolver actors,
            ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"forms.view",ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT LibraryFieldId AS id,ProjectId,Code,Label,FieldType,DefaultConfigJson,IsActive FROM forms.FieldLibrary
WHERE ProjectId=@id OR ProjectId IS NULL ORDER BY Label",new[] {SqlDatabase.G("id",projectId)},ct)).First);
        });
        api.MapProc("/field-library", "forms.usp_SaveLibraryField", null,
            G("ProjectId",false),S("Name",true),S("Code"),S("FieldType",true),J("DefaultConfigJson",false),O("LibraryFieldId"));

        api.MapGet("/projects/{projectId:long}/forms", async (long projectId,HttpContext ctx,ActorResolver actors,
            ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"forms.view",ct);
            return Results.Ok((await db.QueryAsync("SELECT FormId AS id,Code,Name,Description,DraftJson,LiveVersionId,IsActive,CreatedAt,UpdatedAt FROM forms.Definitions WHERE ProjectId=@id ORDER BY UpdatedAt DESC",
                new[] {SqlDatabase.G("id",projectId)},ct)).First);
        });
        api.MapGet("/projects/{projectId:long}/forms/{formId:long}", async (long projectId, long formId,HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"forms.view",ct);
            var result = await db.QueryAsync(@"
SELECT FormId AS id,Code,Name,Description,DraftJson,LiveVersionId,IsActive FROM forms.Definitions WHERE ProjectId=@project AND FormId=@form;
SELECT v.FormVersionId,v.VersionNumber,v.DefinitionJson,v.PublishedAt FROM forms.Versions v
JOIN forms.Definitions d ON d.FormId=v.FormId WHERE d.ProjectId=@project AND d.FormId=@form ORDER BY v.VersionNumber DESC",
                new[] {SqlDatabase.G("project",projectId),SqlDatabase.G("form",formId)},ct);
            return result.First.Count==0 ? (IResult)Results.NotFound() : Results.Ok(new { form=result.First[0], versions=result.Sets[1] });
        });
        api.MapProc("/projects/{projectId:long}/forms", "forms.usp_CreateDefinition", "admin",
            G("ProjectId"),S("Code"),S("Name",true),S("Description"),O("FormId"));
        api.MapProc("/forms/{formId:long}/draft", "forms.usp_SaveDraft", null,G("FormId"),J("DefinitionJson"));
        api.MapProc("/forms/{formId:long}/publish", "forms.usp_Publish", null,G("FormId"),O("VersionId"));

        api.MapGet("/projects/{projectId:long}/workflows", async (long projectId,HttpContext ctx,ActorResolver actors,
            ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"workflows.view",ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT WorkflowId AS id,Code,Name,DraftGraphJson,LiveVersionId,IsActive,CreatedAt,UpdatedAt
FROM flow.Definitions WHERE ProjectId=@id ORDER BY UpdatedAt DESC",new[] {SqlDatabase.G("id",projectId)},ct)).First);
        });
        api.MapGet("/projects/{projectId:long}/workflows/{workflowId:long}", async (long projectId,long workflowId,
            HttpContext ctx,ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"workflows.view",ct);
            var result = await db.QueryAsync(@"
SELECT WorkflowId AS id,Code,Name,DraftGraphJson,LiveVersionId,IsActive FROM flow.Definitions WHERE WorkflowId=@wf AND ProjectId=@proj;
SELECT v.WorkflowVersionId,v.VersionNumber,v.GraphJson,v.PublishedAt FROM flow.Versions v
JOIN flow.Definitions w ON w.WorkflowId=v.WorkflowId WHERE w.WorkflowId=@wf AND w.ProjectId=@proj ORDER BY v.VersionNumber DESC",
                new[] {SqlDatabase.G("wf",workflowId),SqlDatabase.G("proj",projectId)},ct);
            return result.First.Count==0?(IResult)Results.NotFound():Results.Ok(new { workflow=result.First[0],versions=result.Sets[1] });
        });
        api.MapProc("/projects/{projectId:long}/workflows", "flow.usp_CreateDefinition", "admin",
            G("ProjectId"),S("Code"),S("Name",true),O("WorkflowId"));
        api.MapProc("/workflows/{workflowId:long}/draft", "flow.usp_SaveDraft",null,G("WorkflowId"),J("GraphJson"));
        api.MapProc("/workflows/{workflowId:long}/publish", "flow.usp_Publish",null,G("WorkflowId"),O("VersionId"));

        api.MapGet("/projects/{projectId:long}/case-types", async (long projectId,HttpContext ctx,ActorResolver actors,
            ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"project.view",ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT t.CaseTypeId AS id,t.Code,t.Name,t.LiveVersionId,t.DraftJson,t.IsActive,t.UpdatedAt,
 v.VersionNumber,v.PublishedConfigJson FROM core.CaseTypes t LEFT JOIN core.CaseTypeVersions v
ON v.CaseTypeVersionId=t.LiveVersionId WHERE t.ProjectId=@id ORDER BY t.Name",
                new[] {SqlDatabase.G("id",projectId)},ct)).First);
        });
        api.MapGet("/projects/{projectId:long}/case-types/{caseTypeId:long}/intake", async (long projectId,long caseTypeId,
            HttpContext ctx,ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"cases.create",ct);
            var result = await db.QueryAsync(@"
SELECT ct.CaseTypeId,ct.Code,ct.Name,ctv.CaseTypeVersionId,ctv.VersionNumber,ctv.PublishedConfigJson,
 fv.FormVersionId,fv.DefinitionJson FROM core.CaseTypes ct
JOIN core.CaseTypeVersions ctv ON ctv.CaseTypeVersionId=ct.LiveVersionId
JOIN forms.Versions fv ON fv.FormVersionId=ctv.IntakeFormVersionId
WHERE ct.CaseTypeId=@ct AND ct.ProjectId=@p AND ct.IsActive=1;
SELECT l.ListId,l.Code,l.Name,l.ParentListId,cl.IsRequired,cl.LockedItemId,cl.SortOrder
FROM core.CaseTypes ct JOIN core.CaseTypeLookups cl ON cl.CaseTypeVersionId=ct.LiveVersionId
JOIN lookup.Lists l ON l.ListId=cl.ListId
WHERE ct.CaseTypeId=@ct AND ct.ProjectId=@p ORDER BY cl.SortOrder",
                new[] {SqlDatabase.G("ct",caseTypeId),SqlDatabase.G("p",projectId)},ct);
            return result.First.Count==0?(IResult)Results.NotFound():Results.Ok(new { caseType=result.First[0],lookups=result.Sets[1] });
        });
        api.MapProc("/projects/{projectId:long}/case-types", "core.usp_CreateCaseType", "admin",
            G("ProjectId"),S("Code"),S("Name",true),O("CaseTypeId"));
        api.MapProc("/case-types/{caseTypeId:long}/publish", "core.usp_PublishCaseType",null,
            G("CaseTypeId"),J("ConfigJson"),O("CaseTypeVersionId"));

        api.MapGet("/projects/{projectId:long}/reports/definitions", async (long projectId,HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User,ct),projectId,ct);
            return Results.Ok((await db.QueryAsync("SELECT ReportId AS id,Code AS code,Name AS name,ConfigJson AS configJson,IsActive AS isActive FROM reports.Definitions WHERE ProjectId=@p ORDER BY Name",
                new[] {SqlDatabase.G("p",projectId)},ct)).First);
        });
        api.MapProc("/projects/{projectId:long}/reports/definitions", "reports.usp_SaveDefinition", "admin",
            G("ProjectId"),S("Name",true),S("Code"),J("ConfigJson"),O("ReportId"));
        api.MapGet("/projects/{projectId:long}/reports/summary", async (long projectId,DateTime? fromUtc,DateTime? toUtc,
            HttpContext ctx,ActorResolver actors,SqlDatabase db,CancellationToken ct) =>
        {
            var actor = await actors.ResolveAsync(ctx.User,ct);
            var result=await db.ProcedureAsync("reports.usp_CaseSummary",new[] {
                SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("ProjectId",projectId),
                new SqlArgument("FromUtc",fromUtc,System.Data.SqlDbType.DateTime2),
                new SqlArgument("ToUtc",toUtc,System.Data.SqlDbType.DateTime2)
            },ct);
            return Results.Ok(new { byStatus=result.First,byType=result.Sets.Count>1?result.Sets[1]:new List<Dictionary<string,object?>>() });
        });
    }
}
