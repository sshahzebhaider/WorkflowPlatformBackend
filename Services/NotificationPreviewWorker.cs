using System.Data;
using WorkflowPlatform.Api.Data;

namespace WorkflowPlatform.Api.Services;

/// <summary>Development preview only. This service never contacts an email/SMS provider.</summary>
public sealed class NotificationPreviewWorker(IServiceScopeFactory scopeFactory,IConfiguration config,
    ILogger<NotificationPreviewWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while(!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if(config.GetValue<string>("Notifications:DeliveryMode")=="Preview")
                {
                    using var scope=scopeFactory.CreateScope();
                    var db=scope.ServiceProvider.GetRequiredService<SqlDatabase>();
                    var batch=await db.ProcedureAsync("notify.usp_ClaimOutbox",
                        new[]{new SqlArgument("BatchSize",10,SqlDbType.Int)},stoppingToken);
                    foreach(var item in batch.First)
                    {
                        var id=(long)item["NotificationId"]!;
                        await db.ProcedureAsync("notify.usp_RecordDelivery",new[] {
                            SqlDatabase.G("NotificationId",id),SqlDatabase.S("Outcome","Preview"),
                            SqlDatabase.S("Error","Development preview only. Message was NOT sent.")},stoppingToken);
                    }
                    // Preview mode never sends a message but must not trap test cases
                    // forever at notification nodes. Resume only after outbox is marked Preview.
                    var ready=(await db.QueryAsync(@"SELECT TOP(30) sn.InstanceId,sn.NodeId
FROM work.SystemNotifications sn JOIN notify.Outbox o ON o.NotificationId=sn.NotificationId
WHERE sn.ResumedAt IS NULL AND o.State='Preview' ORDER BY o.NotificationId",[],stoppingToken)).First;
                    foreach(var item in ready)
                    {
                        try
                        {
                            await db.ProcedureAsync("work.usp_ResumeSystemNode",new[]{
                                SqlDatabase.G("InstanceId",Convert.ToInt64(item["InstanceId"])),
                                SqlDatabase.G("NodeId",Convert.ToInt64(item["NodeId"]))},stoppingToken);
                        }
                        catch(Exception ex){logger.LogWarning(ex,"Preview notification-node continuation failed");}
                    }
                }
            }
            catch(Exception ex) when(!stoppingToken.IsCancellationRequested)
            { logger.LogError(ex,"Notification preview pump failed"); }
            await Task.Delay(TimeSpan.FromSeconds(10),stoppingToken);
        }
    }
}
