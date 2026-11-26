using System.Data;
using System.Text.Json;
using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;
using WorkflowPlatform.Api.Services;
using static WorkflowPlatform.Api.Api.ProcedureApi;

namespace WorkflowPlatform.Api.Api;

public static class WorkEndpoints
{
    public static void MapWorkEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/projects/{projectId:long}/cases",async(long projectId,int? skip,int? take,string? search, HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await access.RequireAsync(actor,projectId,"cases.view",ct);
            var limit=Math.Clamp(take??30,1,100); var offset=Math.Max(skip??0,0);
            if(search?.Length>200)throw new ArgumentException("Case search is limited to 200 characters.");
            var result=await db.QueryAsync(@"
SELECT c.CaseId AS id,c.ReferenceNo AS reference,c.Title,c.Status,c.Priority,c.CreatedBy,
 c.CreatedAt,c.DueAt,c.ClosedAt,c.CaseTypeVersionId,
 (SELECT v.CaseTypeId FROM core.CaseTypeVersions v WHERE v.CaseTypeVersionId=c.CaseTypeVersionId) AS CaseTypeId,
 (SELECT COUNT_BIG(*) FROM work.Instances i JOIN work.Tasks t ON t.InstanceId=i.InstanceId WHERE i.CaseId=c.CaseId AND t.Status='Open') AS OpenTaskCount,
 CASE WHEN c.CreatedBy=@actor THEN 'Creator' ELSE 'Participant' END AS Visibility
FROM work.Cases c
WHERE c.ProjectId=@project AND (@search IS NULL OR CHARINDEX(@search,c.ReferenceNo)>0 OR CHARINDEX(@search,c.Title)>0) AND (
 auth.fn_IsAdmin(@actor,@project)=1 OR c.CreatedBy=@actor
 OR EXISTS(SELECT 1 FROM work.Instances inst JOIN work.Tasks t ON t.InstanceId=inst.InstanceId
 LEFT JOIN teams.Members m ON m.TeamId=t.TeamId AND m.UserId=@actor AND m.IsActive=1
 WHERE inst.CaseId=c.CaseId AND (t.AssignedTo=@actor OR t.CompletedBy=@actor OR m.UserId IS NOT NULL)))
ORDER BY c.CreatedAt DESC,c.CaseRowId DESC OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY;
SELECT COUNT_BIG(*) AS Total,COUNT_BIG(CASE WHEN c.ClosedAt IS NULL THEN 1 END) AS OpenCount
FROM work.Cases c WHERE c.ProjectId=@project AND (@search IS NULL OR CHARINDEX(@search,c.ReferenceNo)>0 OR CHARINDEX(@search,c.Title)>0) AND (
 auth.fn_IsAdmin(@actor,@project)=1 OR c.CreatedBy=@actor OR EXISTS(
 SELECT 1 FROM work.Instances inst JOIN work.Tasks t ON t.InstanceId=inst.InstanceId
 LEFT JOIN teams.Members m ON m.TeamId=t.TeamId AND m.UserId=@actor AND m.IsActive=1
 WHERE inst.CaseId=c.CaseId AND (t.AssignedTo=@actor OR t.CompletedBy=@actor OR m.UserId IS NOT NULL)));",
                new[] {SqlDatabase.G("actor",actor.UserId),SqlDatabase.G("project",projectId),
                    new SqlArgument("skip",offset,SqlDbType.Int),new SqlArgument("take",limit,SqlDbType.Int),SqlDatabase.S("search",string.IsNullOrWhiteSpace(search)?null:search.Trim())},ct);
            var counts=result.Sets.ElementAtOrDefault(1)?.FirstOrDefault();
            return Results.Ok(new {items=result.First,skip=offset,take=limit,total=counts?["Total"]??0L,openCount=counts?["OpenCount"]??0L});
        });
        api.MapGet("/projects/{projectId:long}/cases/{caseId:long}",async(long projectId,long caseId,HttpContext ctx,
            ActorResolver actors,SqlDatabase db,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            var r=await db.ProcedureAsync("work.usp_GetCaseDetails",new[] {
                SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("ProjectId",projectId),
                SqlDatabase.G("CaseId",caseId)},ct);
            if(r.First.Count==0)return Results.NotFound();
            // The stored procedure already checked case visibility. Return only mapped output
            // fields, not raw responses or confidential integration credentials.
            var integrations=(await db.QueryAsync(@"
SELECT ExecutionId,OperationId,Status,FinishedAt,MappedFieldsJson
FROM integration.Executions WHERE CaseId=@case AND Status='Succeeded'
ORDER BY ExecutionId",new[]{SqlDatabase.G("case",caseId)},ct)).First;
            var rcaOptions = (await db.QueryAsync(@"SELECT p.FieldKey,JSON_QUERY(p.ConfigJson,'$.options') AS OptionsJson
FROM core.ProjectRcaFields p JOIN OPENJSON(@snapshot) WITH(FieldKey NVARCHAR(90) '$.FieldKey', OptionsJson NVARCHAR(MAX) '$.OptionsJson' AS JSON) f ON f.FieldKey COLLATE Latin1_General_BIN2=p.FieldKey COLLATE Latin1_General_BIN2
WHERE p.ProjectId=@project AND f.OptionsJson IS NULL",new[]{SqlDatabase.G("project",projectId),SqlDatabase.S("snapshot",(r.First[0]["RcaFieldsSnapshotJson"] as string)??"[]")},ct)).First;
            return Results.Ok(new {caseRecord=r.First[0],rcaOptions,
                tasks=r.Sets.ElementAtOrDefault(1)??new(),events=r.Sets.ElementAtOrDefault(2)??new(),
                answers=r.Sets.ElementAtOrDefault(3)??new(),attachments=r.Sets.ElementAtOrDefault(4)??new(),
                integrations});
        });
        // Step 1 of new-case lodging: fetch the approved external data BEFORE intake.
        // Permission is cases.create, never Platform Admin test rights.
        api.MapPost("/projects/{projectId:long}/case-types/{caseTypeId:long}/data-lookup",
            async(long projectId,long caseTypeId,HttpContext ctx,ActorResolver actors,
                ProjectAccess access,LodgementIntegration lodgement,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await access.RequireAsync(actor,projectId,"cases.create",ct);
            var request=await ctx.Request.ReadFromJsonAsync<OperationTestRequest>(cancellationToken:ct);
            var result=await lodgement.PreviewAsync(projectId,caseTypeId,actor.UserId,
                request?.Inputs??new Dictionary<string,JsonElement>(),ct);
            return Results.Ok(new {result.PreviewId,result.PreviewToken,result.HttpStatus,
                fields=result.Fields,truncated=result.Truncated,intakeValues=result.IntakeValues,records=result.Records});
        });
        api.MapPost("/projects/{projectId:long}/cases",async(long projectId,HttpContext ctx,
            ActorResolver actors,ProjectAccess access,SqlDatabase db,FormRules rules,LodgementIntegration lodgement,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await access.RequireAsync(actor,projectId,"cases.create",ct);
            var body=await ctx.Request.ReadFromJsonAsync<CreateCaseRequest>(cancellationToken:ct)
                ?? throw new ArgumentException("Case request body required.");
            if (body.CaseTypeId==0) throw new ArgumentException("caseTypeId is required.");
            if (body.IntakeJson.ValueKind != JsonValueKind.Object) throw new ArgumentException("intakeJson must be an object.");
            await rules.ValidateIntakeAsync(projectId,body.CaseTypeId,body.IntakeJson,ct);
            var key=ctx.Request.Headers["Idempotency-Key"].FirstOrDefault();
            if(!string.IsNullOrWhiteSpace(key) && (key.Length>120 ||
                !key.All(c=>char.IsLetterOrDigit(c)||c is '-' or '_' or ':')))
                throw new ArgumentException("Idempotency-Key must contain only letters, numbers, dash, underscore or colon, max 120 characters.");
            // A retry of an already committed request must never execute its external API again.
            if(!string.IsNullOrWhiteSpace(key))
            {
                var existing=(await db.QueryAsync(@"SELECT CaseId AS caseId,ReferenceNo AS referenceNo
FROM work.Cases WHERE ProjectId=@project AND CreatedBy=@actor AND IdempotencyKey=@key",
                    new[]{SqlDatabase.G("project",projectId),SqlDatabase.G("actor",actor.UserId),SqlDatabase.S("key",key)},ct)).First;
                if(existing.Count>0)return Results.Ok(new {data=existing,outputs=new Dictionary<string,object?> {
                    ["CaseId"]=existing[0]["caseId"],["ReferenceNo"]=existing[0]["referenceNo"] }});
            }
            // A Case Type with an operation MUST have a verified pre-intake receipt.
            // SQL validates/consumes that receipt atomically with case creation.
            var configured=await lodgement.GetOperationAsync(projectId,body.CaseTypeId,ct);
            if(configured is null && (body.PreviewId.HasValue || body.PreviewToken is not null))
                throw new ArgumentException("The selected Case Type does not use a data-source lookup.");
            if(configured is not null && (!body.PreviewId.HasValue || body.PreviewId<=0))
                throw new ArgumentException("Fetch and review the required data-source values before creating the case.");
            var args=new List<SqlArgument> {SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("ProjectId",projectId),
                SqlDatabase.G("CaseTypeId",body.CaseTypeId),SqlDatabase.S("IntakeJson",body.IntakeJson.GetRawText()),
                SqlDatabase.S("ClassificationJson",body.ClassificationJson.ValueKind==JsonValueKind.Object?body.ClassificationJson.GetRawText():"{}"),
                SqlDatabase.S("Title",body.Title),SqlDatabase.S("IdempotencyKey",key),
                new("CaseId",null,SqlDbType.BigInt,IsOutput:true),new("ReferenceNo",null,SqlDbType.NVarChar,55,IsOutput:true)};
            var r=configured is null
                ? await db.ProcedureAsync("work.usp_CreateCase",args,ct)
                : await db.ProcedureAsync("integration.usp_CreateCaseFromPreview",args.Concat(new SqlArgument[]{
                    SqlDatabase.G("PreviewId",body.PreviewId),
                    new("PreviewTokenHash",LodgementIntegration.HashPreviewToken(body.PreviewToken),SqlDbType.VarBinary,32)
                }),ct);
            return Results.Ok(new {data=r.First,outputs=r.Outputs});
        });
        api.MapGet("/projects/{projectId:long}/tasks/mine",async(long projectId,bool? includeCompleted,HttpContext ctx,
            ActorResolver actors,SqlDatabase db,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            var r=await db.ProcedureAsync("work.usp_GetMyTasks",new[] {SqlDatabase.G("ActorUserId",actor.UserId),
                SqlDatabase.G("ProjectId",projectId),new SqlArgument("IncludeCompleted",includeCompleted??false,SqlDbType.Bit)},ct);
            return Results.Ok(r.First);
        });
        api.MapGet("/projects/{projectId:long}/teams/{teamId:long}/tasks",async(long projectId,long teamId,
            HttpContext ctx,ActorResolver actors,SqlDatabase db,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            var rows=(await db.QueryAsync(@"
SELECT t.TaskId,t.AssignedTo,t.RoutingStage,t.Priority,t.Status,t.DueAt,
 c.CaseId,c.ReferenceNo,c.Title,n.Label AS StepName
FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId
JOIN work.Cases c ON c.CaseId=i.CaseId JOIN flow.Nodes n ON n.NodeId=t.NodeId
WHERE c.ProjectId=@project AND t.TeamId=@team
AND (auth.fn_IsAdmin(@actor,@project)=1 OR EXISTS
 (SELECT 1 FROM teams.Members m WHERE m.UserId=@actor AND m.TeamId=@team
 AND m.IsActive=1 AND m.TeamRole IN('TeamLead','UnitHead')))
ORDER BY t.DueAt,t.CreatedAt DESC",
                new[] {SqlDatabase.G("actor",actor.UserId),SqlDatabase.G("project",projectId),SqlDatabase.G("team",teamId)},ct)).First;
            return Results.Ok(rows);
        });
        api.MapPost("/tasks/{taskId:long}/complete",async(long taskId,HttpContext ctx,ActorResolver actors,
            SqlDatabase db,FormRules rules,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            var body=await ctx.Request.ReadFromJsonAsync<CompleteTaskRequest>(cancellationToken:ct)
                ?? throw new ArgumentException("Action is required.");
            if (string.IsNullOrWhiteSpace(body.Action)) throw new ArgumentException("action is required.");
            var answers=body.AnswersByFormJson.ValueKind==JsonValueKind.Object?body.AnswersByFormJson:JsonSerializer.SerializeToElement(new {});
            await rules.ValidateStepAnswersAsync(taskId,answers,ct);
            // The API validates keys by immutable FormVersionId. The original SQL stored
            // procedure expects keys by FormId. Translate after validation, on the server,
            // using the task's pinned NodeForms; never trust client-provided form IDs.
            var formRows=(await db.QueryAsync(@"SELECT nf.FormVersionId,v.FormId
FROM work.Tasks t JOIN flow.NodeForms nf ON nf.NodeId=t.NodeId
JOIN forms.Versions v ON v.FormVersionId=nf.FormVersionId WHERE t.TaskId=@task",
                new[]{SqlDatabase.G("task",taskId)},ct)).First;
            var sqlAnswers=new Dictionary<string,JsonElement>();
            foreach(var row in formRows)
            {
                var formVersionId=(long)row["FormVersionId"]!;
                var formId=(long)row["FormId"]!;
                if(answers.TryGetProperty(formVersionId.ToString(),out var formValues))
                    sqlAnswers[formId.ToString()]=formValues.Clone();
            }
            var r=await db.ProcedureAsync("work.usp_CompleteTask",new[] {
                SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("TaskId",taskId),
                SqlDatabase.S("Action",body.Action),SqlDatabase.S("AnswersByFormJson",JsonSerializer.Serialize(sqlAnswers)),
                SqlDatabase.S("Comment",body.Comment)},ct);
            return Results.Ok(new { data=r.First, message="Task action recorded" });
        });
        api.MapProc("/tasks/{taskId:long}/forward", "work.usp_ForwardTask",null,G("TaskId"),G("ToUserId"));
        api.MapProc("/tasks/{taskId:long}/assign", "work.usp_AssignUnassignedTask",null,G("TaskId"),G("ToUserId"));
        // Manager-only, atomic redistribution of open tasks within their existing team.
        // The stored procedure validates membership, role compatibility and case scope.
        api.MapProc("/projects/{projectId:long}/teams/{teamId:long}/tasks/rebalance",
            "work.usp_RebalanceTeamTasks", null,
            G("ProjectId"),G("TeamId"),J("TaskIdsJson"),G("ToUserId"),S("Reason"));
        api.MapProc("/tasks/{taskId:long}/force-intimation", "work.usp_ForceIntimation",null,
            G("TaskId"),S("Priority",true),S("Reason",true),O("NotificationId"));
        api.MapProc("/cases/{caseId:long}/rca", "work.usp_SubmitRca",null,G("CaseId"),
            S("Summary"),J("FieldsJson"),G("RootReasonItemId",false),J("FormAnswersJson",false));
    }
}
public sealed record CreateCaseRequest(long CaseTypeId,JsonElement IntakeJson,JsonElement ClassificationJson,string? Title, long? PreviewId=null, string? PreviewToken=null);
public sealed record CompleteTaskRequest(string Action,JsonElement AnswersByFormJson,string? Comment=null);
