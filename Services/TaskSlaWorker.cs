using System.Data;
using WorkflowPlatform.Api.Data;

namespace WorkflowPlatform.Api.Services;

/// <summary>Escalates overdue human work and queues notifications. Never auto-approves or silently completes it.</summary>
public sealed class TaskSlaWorker(IServiceScopeFactory scopeFactory,ILogger<TaskSlaWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        while(!ct.IsCancellationRequested)
        {
            try
            {
                using var scope=scopeFactory.CreateScope();
                var db=scope.ServiceProvider.GetRequiredService<SqlDatabase>();
                foreach(var job in new[]{"work.usp_EscalateOverdueTasks","work.usp_RecordCaseTatBreaches","integration.usp_PurgeLodgementPreviews"})
                {
                    try { await db.ProcedureAsync(job,job=="integration.usp_PurgeLodgementPreviews" ? Array.Empty<SqlArgument>() : new[]{new SqlArgument("BatchSize",50,SqlDbType.Int)},ct); }
                    catch(OperationCanceledException) when(ct.IsCancellationRequested) { throw; }
                    catch(Exception ex) { logger.LogError(ex,"Scheduled SLA job {Job} failed",job); }
                }
            }
            catch(OperationCanceledException) when(ct.IsCancellationRequested){break;}
            catch(Exception ex){logger.LogError(ex,"Task SLA escalation pump failed");}
            try{await Task.Delay(TimeSpan.FromSeconds(60),ct);}
            catch(OperationCanceledException) when(ct.IsCancellationRequested){break;}
        }
    }
}
