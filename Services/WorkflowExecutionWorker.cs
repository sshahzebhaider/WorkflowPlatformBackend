using System.Data;
using System.Text.Json;
using WorkflowPlatform.Api.Data;

namespace WorkflowPlatform.Api.Services;

/// <summary>Durable, concurrency-safe polling for REST and timer system nodes.
/// HTTP calls are made only for database-approved operations, never arbitrary URLs.</summary>
public sealed class WorkflowExecutionWorker(IServiceScopeFactory scopeFactory,IConfiguration config,
    ILogger<WorkflowExecutionWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while(!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope=scopeFactory.CreateScope();
                var db=scope.ServiceProvider.GetRequiredService<SqlDatabase>();
                await ResumeSucceededAsync(db,stoppingToken);
                await ResumeTimersAsync(db,stoppingToken);
                if(config.GetValue<bool>("Integration:Enabled"))
                    await ExecuteIntegrationsAsync(db,scope.ServiceProvider.GetRequiredService<OperationTester>(),stoppingToken);
            }
            catch(OperationCanceledException) when(stoppingToken.IsCancellationRequested) { break; }
            catch(Exception e) { logger.LogError(e,"Workflow execution pump failed"); }
            try { await Task.Delay(TimeSpan.FromSeconds(5),stoppingToken); }
            catch(OperationCanceledException) when(stoppingToken.IsCancellationRequested) { break; }
        }
    }

    private async Task ResumeSucceededAsync(SqlDatabase db,CancellationToken ct)
    {
        var pending=(await db.QueryAsync(@"
SELECT TOP(20) i.InstanceId,e.NodeId,e.ExecutionId FROM integration.Executions e
JOIN work.Instances i ON i.CaseId=e.CaseId
WHERE e.Status='Succeeded' AND e.ResumedAt IS NULL AND e.NodeId IS NOT NULL
AND i.Status IN('Running','Waiting') ORDER BY e.ExecutionId",[],ct)).First;
        foreach(var e in pending)
        {
            try { await db.ProcedureAsync("work.usp_ResumeSystemNode",new[]{
                SqlDatabase.G("InstanceId",Convert.ToInt64(e["InstanceId"])),
                SqlDatabase.G("NodeId",Convert.ToInt64(e["NodeId"]))},ct); }
            catch(Exception ex) { logger.LogWarning(ex,"Cannot resume successful integration {ExecutionId}",e["ExecutionId"]); }
        }
    }
    private async Task ResumeTimersAsync(SqlDatabase db,CancellationToken ct)
    {
        var timers=(await db.QueryAsync(@"
SELECT TOP(20) InstanceId,NodeId,TimerId FROM work.PendingTimers
WHERE Status='Pending' AND WakeAtUtc<=SYSUTCDATETIME() ORDER BY WakeAtUtc,TimerId",[],ct)).First;
        foreach(var timer in timers)
        {
            try { await db.ProcedureAsync("work.usp_ResumeSystemNode",new[]{
                SqlDatabase.G("InstanceId",Convert.ToInt64(timer["InstanceId"])),
                SqlDatabase.G("NodeId",Convert.ToInt64(timer["NodeId"]))},ct); }
            catch(Exception ex) { logger.LogWarning(ex,"Cannot resume workflow timer {TimerId}",timer["TimerId"]); }
        }
    }
    private async Task ExecuteIntegrationsAsync(SqlDatabase db,OperationTester tester,CancellationToken ct)
    {
        // The database procedure holds queue locks, so parallel API hosts never claim
        // the same Pending execution at once. It also reclaims crashed workers.
        var claimed=(await db.ProcedureAsync("integration.usp_ClaimWorkflowExecutions",
            new[]{new SqlArgument("BatchSize",1,SqlDbType.Int)},ct)).First;
        foreach(var execution in claimed)
        {
            var id=Convert.ToInt64(execution["ExecutionId"]);
            var attempt=Convert.ToInt64(execution["ClaimVersion"]);
            try
            {
                var caseId=Convert.ToInt64(execution["CaseId"]);
                var rows=(await db.QueryAsync(@"
SELECT TOP(1) c.CurrentValuesJson,c.ClassificationJson,c.Title,c.ReferenceNo
FROM work.Cases c WHERE c.CaseId=@case",new[]{SqlDatabase.G("case",caseId)},ct)).First;
                if(rows.Count==0)throw new InvalidOperationException("Case is missing for workflow integration.");
                var row=rows[0];
                var values=new Dictionary<string,JsonElement>(StringComparer.Ordinal);
                static void AddInputs(Dictionary<string,JsonElement> result,string? json,string prefix)
                {
                    if(string.IsNullOrWhiteSpace(json))return;
                    using var parsed=JsonDocument.Parse(json);
                    if(parsed.RootElement.ValueKind!=JsonValueKind.Object)throw new ArgumentException("Case context is not an object.");
                    foreach(var field in parsed.RootElement.EnumerateObject().Take(500))
                    {
                        result[$"{prefix}.{field.Name}"]=field.Value.Clone();
                        if(prefix=="fields")result.TryAdd(field.Name,field.Value.Clone());
                    }
                }
                AddInputs(values,row["CurrentValuesJson"]?.ToString(),"fields");
                AddInputs(values,row["ClassificationJson"]?.ToString(),"classification");
                values["title"]=JsonSerializer.SerializeToElement(row["Title"]?.ToString()??"");
                values["reference"]=JsonSerializer.SerializeToElement(row["ReferenceNo"]?.ToString()??"");
                values["caseId"]=JsonSerializer.SerializeToElement(caseId);
                var operationId=Convert.ToInt64(execution["OperationId"]);
                var response=await tester.RunAsync(operationId,values,ct,execution["IdempotencyKey"]?.ToString(),projectId:Convert.ToInt64(execution["ProjectId"]));
                await db.ProcedureAsync("integration.usp_RecordResult",new[]{
                    SqlDatabase.G("ExecutionId",id),SqlDatabase.G("ClaimAttempt",attempt),new SqlArgument("Succeeded",true,SqlDbType.Bit),
                    SqlDatabase.S("MappedFieldsJson",JsonSerializer.Serialize(response.Mapped))},ct);
                // If resume fails after recording success, the next pass resumes it safely.
                await ResumeSucceededAsync(db,ct);
            }
            catch(OperationCanceledException) when(ct.IsCancellationRequested) { throw; }
            catch(Exception ex)
            {
                logger.LogError(ex,"Workflow integration {ExecutionId} failed",id);
                try { await db.ProcedureAsync("integration.usp_RecordResult",new[]{
                    SqlDatabase.G("ExecutionId",id),SqlDatabase.G("ClaimAttempt",attempt),new SqlArgument("Succeeded",false,SqlDbType.Bit),
                    SqlDatabase.S("Error",ex.GetType().Name)},ct); }
                catch(Exception recordError) { logger.LogError(recordError,"Unable to record integration failure {ExecutionId}",id); }
            }
        }
    }
}
