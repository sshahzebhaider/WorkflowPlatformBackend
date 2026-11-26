using System.Data;
using System.Text.Json;
using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;
using WorkflowPlatform.Api.Services;
using static WorkflowPlatform.Api.Api.ProcedureApi;

namespace WorkflowPlatform.Api.Api;

public static class IntegrationEndpoints
{
    public static void MapIntegrationEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/data-sources",async(HttpContext ctx,ActorResolver actors,ProjectAccess access,
            SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User,ct),null,ct);
            // Never expose CredentialSecretRef or credential values to the browser.
            return Results.Ok((await db.QueryAsync(@"SELECT DataSourceId AS id,Code,Name,Kind,BaseUrl,Description,IsActive,
 CAST(CASE WHEN EXISTS(SELECT 1 FROM integration.DataSourceApprovals a
 WHERE a.DataSourceId=integration.DataSources.DataSourceId AND a.IsApproved=1
 AND a.ApprovedBaseUrl=integration.DataSources.BaseUrl) THEN 1 ELSE 0 END AS BIT) AS HostApproved,
 CASE WHEN CredentialSecretRef LIKE 'BEARER:%' THEN 'Bearer' WHEN CredentialSecretRef LIKE 'APIKEY:%' THEN 'ApiKey' ELSE 'None' END AS AuthenticationScheme,
 CAST(CASE WHEN CredentialSecretRef IS NULL THEN 0 ELSE 1 END AS BIT) AS CredentialConfigured
 FROM integration.DataSources ORDER BY Name",[],ct)).First);
        });
        // Never accept arbitrary hosts or URLs from the browser: approval is derived from
        // the saved source URL, and execution still validates DNS/IP at connect time.
        api.MapPost("/data-sources/{sourceId:long}/host-approval",async(long sourceId,
            HostApprovalRequest request,HttpContext ctx,ActorResolver actors,ProjectAccess access,
            SqlDatabase db,IConfiguration config,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await access.RequireAdminAsync(actor,null,ct);
            var urls=(await db.QueryAsync(@"SELECT BaseUrl FROM integration.DataSources
WHERE DataSourceId=@id AND Kind='REST' AND IsActive=1",
                new[]{SqlDatabase.G("id",sourceId)},ct)).First;
            if(urls.Count==0)return Results.NotFound();
            var text=urls[0]["BaseUrl"]?.ToString();
            if(!Uri.TryCreate(text,UriKind.Absolute,out var uri) || (request.Approved && !IntegrationDestinationPolicy.IsAllowed(uri,config)) || uri.UserInfo.Length>0 || !string.IsNullOrEmpty(uri.Query)
                || !string.IsNullOrEmpty(uri.Fragment) || uri.Host.Length>253
                || System.Net.IPAddress.TryParse(uri.Host,out _)
                || uri.IdnHost.Equals("localhost",StringComparison.OrdinalIgnoreCase)
                || uri.IdnHost.EndsWith(".localhost",StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException("An approved destination hostname, protocol and port are required.");
            await db.ProcedureAsync("integration.usp_SetDataSourceApproval",new[] {
                SqlDatabase.G("DataSourceId",sourceId),SqlDatabase.S("ExpectedBaseUrl",text),
                SqlDatabase.S("ApprovedHost",uri.IdnHost.ToLowerInvariant()),
                new SqlArgument("Approved",request.Approved,SqlDbType.Bit),
                SqlDatabase.G("ActorUserId",actor.UserId)},ct);
            return Results.Ok(new {approved=request.Approved,host=uri.IdnHost});
        });
        api.MapGet("/data-sources/{sourceId:long}/operations",async(long sourceId,HttpContext ctx,ActorResolver actors,
            ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User,ct),null,ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT OperationId AS id,Code,Name,HttpMethod,UrlPath,RequestTemplateJson,ResponseMapJson,HeaderTemplateJson,RequestParamsJson,IsActive
FROM integration.Operations WHERE DataSourceId=@id ORDER BY Name",new[]{SqlDatabase.G("id",sourceId)},ct)).First);
        });
        api.MapGet("/projects/{projectId:long}/data-sources",async(long projectId,HttpContext ctx,ActorResolver actors,
            ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            // Case creators need approved source names to render their published Case Type.
            // This read does not expose credential references or enable source editing.
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"project.view",ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT s.DataSourceId AS id,s.Code,s.Name,s.Kind,s.BaseUrl,s.Description
FROM integration.ProjectDataSources p JOIN integration.DataSources s ON s.DataSourceId=p.DataSourceId
WHERE p.ProjectId=@p AND s.IsActive=1",
                new[] {SqlDatabase.G("p",projectId)},ct)).First);
        });
        api.MapGet("/projects/{projectId:long}/data-sources/{sourceId:long}/operations",async(
            long projectId,long sourceId,HttpContext ctx,ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            // Read-only operation input definitions are needed by the pre-intake form.
            await access.RequireAsync(actor,projectId,"project.view",ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT o.OperationId AS id,o.Code,o.Name,o.HttpMethod,o.UrlPath,o.RequestTemplateJson,o.ResponseMapJson,o.RequestParamsJson,o.IsActive
FROM integration.Operations o
JOIN integration.DataSources s ON s.DataSourceId=o.DataSourceId
JOIN integration.ProjectDataSources p ON p.DataSourceId=s.DataSourceId
WHERE p.ProjectId=@project AND o.DataSourceId=@source AND s.IsActive=1 AND o.IsActive=1
ORDER BY o.Name",new[]{SqlDatabase.G("project",projectId),SqlDatabase.G("source",sourceId)},ct)).First);
        });
        api.MapProc("/data-sources", "integration.usp_SaveDataSource", "platformAdmin",
            S("Name",true),S("Code"),S("Kind"),S("BaseUrl"),S("CredentialSecretRef"),S("Description"),O("DataSourceId"));
        api.MapProc("/data-sources/{dataSourceId:long}/operations", "integration.usp_SaveOperation", "platformAdmin",
            G("DataSourceId"),S("Name",true),S("Code"),S("HttpMethod",true),S("UrlPath",true),
            J("RequestTemplateJson",false),J("ResponseMapJson",false),J("HeaderTemplateJson",false),J("RequestParamsJson",false),O("OperationId"));
        // Global connection diagnostics: a Platform Admin can verify an integration
        // before assigning it to a project. This endpoint never changes
        // integration.ProjectDataSources. Runtime calls still require approval.
        api.MapPost("/data-sources/operations/{operationId:long}/test",
            async(long operationId,HttpContext ctx,ActorResolver actors,ProjectAccess access,
                SqlDatabase db,OperationTester tester,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await access.RequireAdminAsync(actor,null,ct);
            // OperationTester validates source+operation status, HTTPS host allowlist,
            // inputs and request limits. Do not accept a URL or credentials from the client.
            var input=await ctx.Request.ReadFromJsonAsync<OperationTestRequest>(cancellationToken:ct);
            await db.ProcedureAsync("audit.usp_Write",new[] {
                SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.S("EntityType","DataSourceOperation"),
                SqlDatabase.G("EntityId",operationId),SqlDatabase.S("ActionCode","PlatformTestStarted")
            },ct);
            try
            {
                var result=await tester.RunAsync(operationId,input?.Inputs??new(),ct,readOnly:true);
                await db.ProcedureAsync("audit.usp_Write",new[] {
                    SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.S("EntityType","DataSourceOperation"),
                    SqlDatabase.G("EntityId",operationId),SqlDatabase.S("ActionCode","PlatformTestSucceeded"),
                    SqlDatabase.S("DetailsJson",JsonSerializer.Serialize(new { httpStatus=result.Status }))
                },ct);
                return Results.Ok(new { status=result.Status,body=result.Body,mapped=result.Mapped });
            }
            catch (Exception ex) when (ex is ArgumentException or InvalidOperationException
                or HttpRequestException or TaskCanceledException or JsonException)
            {
                // No raw request, token, response or exception message in audit events.
                await db.ProcedureAsync("audit.usp_Write",new[] {
                    SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.S("EntityType","DataSourceOperation"),
                    SqlDatabase.G("EntityId",operationId),SqlDatabase.S("ActionCode","PlatformTestFailed"),
                    SqlDatabase.S("DetailsJson",JsonSerializer.Serialize(new { errorType=ex.GetType().Name }))
                },ct);
                throw;
            }
        });
        api.MapPost("/projects/{projectId:long}/data-sources/operations/{operationId:long}/test",
            async(long projectId,long operationId,HttpContext ctx,ActorResolver actors,ProjectAccess access,
                SqlDatabase db,OperationTester tester,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await access.RequireAdminAsync(actor,projectId,ct);
            var input=await ctx.Request.ReadFromJsonAsync<OperationTestRequest>(cancellationToken:ct);
            var execution=await db.ProcedureAsync("integration.usp_QueueTest",new[] {
                SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("ProjectId",projectId),
                SqlDatabase.G("OperationId",operationId),new SqlArgument("ExecutionId",null,SqlDbType.BigInt,IsOutput:true)},ct);
            var executionId=(long)execution.Outputs["ExecutionId"]!;
            try
            {
                var result=await tester.RunAsync(operationId,input?.Inputs??new(),ct,projectId:projectId,readOnly:true);
                // Store only mapped fields, not raw external payloads that may contain confidential data.
                await db.ProcedureAsync("integration.usp_RecordResult",new[] {
                    SqlDatabase.G("ExecutionId",executionId),new SqlArgument("Succeeded",true,SqlDbType.Bit),
                    SqlDatabase.S("MappedFieldsJson",JsonSerializer.Serialize(result.Mapped))},ct);
                return Results.Ok(new { executionId, status=result.Status, body=result.Body, mapped=result.Mapped });
            }
            catch(Exception ex) when(ex is ArgumentException or InvalidOperationException or HttpRequestException or TaskCanceledException or JsonException)
            {
                await db.ProcedureAsync("integration.usp_RecordResult",new[] {
                    SqlDatabase.G("ExecutionId",executionId),new SqlArgument("Succeeded",false,SqlDbType.Bit),
                    SqlDatabase.S("Error",ex.Message[..Math.Min(800,ex.Message.Length)])},ct);
                throw;
            }
        });
        api.MapGet("/projects/{projectId:long}/integrations/executions",async(long projectId,HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            await access.RequireAdminAsync(await actors.ResolveAsync(ctx.User,ct),projectId,ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT TOP(100) ExecutionId,CaseId,NodeId,OperationId,Status,AttemptCount,StartedAt,FinishedAt,
 MappedFieldsJson,LastError FROM integration.Executions WHERE ProjectId=@p
ORDER BY StartedAt DESC,ExecutionId DESC",new[]{SqlDatabase.G("p",projectId)},ct)).First);
        });
        api.MapPost("/projects/{projectId:long}/integrations/executions/{executionId:long}/retry",async(long projectId,long executionId,HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await access.RequireAdminAsync(actor,projectId,ct);
            await db.ProcedureAsync("integration.usp_RetryFailedRead",new[]{SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("ProjectId",projectId),SqlDatabase.G("ExecutionId",executionId)},ct);
            return Results.Ok(new {executionId,status="Pending"});
        });
        api.MapProc("/notifications/templates", "notify.usp_SaveTemplate", null,
            G("ProjectId",false),S("Name",true),S("Code"),S("Channel"),S("LanguageCode"),
            S("Subject"),S("Body",true),O("TemplateId"));
        api.MapProc("/projects/{projectId:long}/notifications/rules", "notify.usp_SaveRule", "admin",
            G("ProjectId"),S("EventCode",true),G("TemplateId"),J("RecipientRuleJson",false),O("RuleId"));
        api.MapGet("/projects/{projectId:long}/notifications",async(long projectId,HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct)=>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"notifications.view",ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT TOP(100) NotificationId,CaseId,TaskId,Channel,LanguageCode,State,Attempts,LastError,CreatedAt,SentAt
FROM notify.Outbox WHERE ProjectId=@project ORDER BY CreatedAt DESC",
                new[] {SqlDatabase.G("project",projectId)},ct)).First);
        });
        api.MapGet("/projects/{projectId:long}/notification-rules",async(long projectId,HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct)=>
        {
            await access.RequireAsync(await actors.ResolveAsync(ctx.User,ct),projectId,"notifications.view",ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT RuleId,EventCode,TemplateId,IsEnabled,RecipientRuleJson FROM notify.Rules WHERE ProjectId=@project",
                new[] {SqlDatabase.G("project",projectId)},ct)).First);
        });
        api.MapGet("/notification-templates",async(HttpContext ctx,ActorResolver actors,
            ProjectAccess access,SqlDatabase db,long? projectId,CancellationToken ct)=>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            if (projectId is null) await access.RequireAdminAsync(actor,null,ct);
            else await access.RequireAsync(actor,projectId,"notifications.view",ct);
            return Results.Ok((await db.QueryAsync(@"
SELECT TemplateId,ProjectId,Code,Name,Channel,LanguageCode,SubjectTemplate,BodyTemplate,IsActive
FROM notify.Templates WHERE (@project IS NULL AND ProjectId IS NULL OR ProjectId=@project)",
                new[] {SqlDatabase.G("project",projectId)},ct)).First);
        });
    }
}
public sealed record OperationTestRequest(Dictionary<string,JsonElement>? Inputs);

public sealed record HostApprovalRequest(bool Approved);
