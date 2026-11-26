using System.Data;
using System.Net.Http.Headers;
using System.Net.Mail;
using System.Text;
using System.Text.Json;
using WorkflowPlatform.Api.Data;

namespace WorkflowPlatform.Api.Services;

/// <summary>Live outbox delivery through SendGrid and Twilio. Provider acceptance is NOT proof of delivery.
/// Secrets must come from protected configuration; payloads/credentials are never logged.</summary>
public sealed class NotificationDeliveryWorker(IServiceScopeFactory scopes,IHttpClientFactory clients,
    IConfiguration config,ILogger<NotificationDeliveryWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        while(!ct.IsCancellationRequested)
        {
            try
            {
                if(string.Equals(config["Notifications:DeliveryMode"],"Live",StringComparison.OrdinalIgnoreCase))
                {
                    using var scope=scopes.CreateScope();
                    var db=scope.ServiceProvider.GetRequiredService<SqlDatabase>();
                    var batch=await db.ProcedureAsync("notify.usp_ClaimOutbox",
                        new[]{new SqlArgument("BatchSize",10,SqlDbType.Int)},ct);
                    foreach(var item in batch.First)await DeliverAsync(db,item,ct);
                    await ResumeNodesAsync(db,ct);
                }
            }
            catch(OperationCanceledException) when(ct.IsCancellationRequested){break;}
            catch(Exception e){logger.LogError(e,"Notification delivery pump failed");}
            try{await Task.Delay(TimeSpan.FromSeconds(10),ct);}
            catch(OperationCanceledException) when(ct.IsCancellationRequested){break;}
        }
    }
    private async Task DeliverAsync(SqlDatabase db,Dictionary<string,object?> row,CancellationToken ct)
    {
        var id=Convert.ToInt64(row["NotificationId"]);
        try
        {
            var channel=row["Channel"]?.ToString();
            var dest=row["RecipientAddress"]?.ToString();
            using var parsed=JsonDocument.Parse(row["PayloadJson"]?.ToString()??"{}");
            var payload=parsed.RootElement;
            var subject=payload.TryGetProperty("subject",out var sub)?sub.ToString():"Workflow notification";
            var reference=payload.TryGetProperty("reference",out var r)?r.ToString():"";
            var body=payload.TryGetProperty("body",out var message)?message.ToString():
                $"Workflow update for case {reference}.";
            string? providerId=null;int? httpStatus=null;
            if(channel=="Email")
            {
                if(string.IsNullOrWhiteSpace(dest)||!MailAddress.TryCreate(dest,out _)||subject.Length>300)
                    throw new InvalidOperationException("Notification recipient email is invalid.");
                var key=config["Notifications:SendGrid:ApiKey"];
                var from=config["Notifications:SendGrid:FromEmail"];
                if(string.IsNullOrWhiteSpace(key)||!MailAddress.TryCreate(from,out _))
                    throw new InvalidOperationException("SendGrid delivery is not configured.");
                using var req=new HttpRequestMessage(HttpMethod.Post,"https://api.sendgrid.com/v3/mail/send");
                req.Headers.Authorization=new AuthenticationHeaderValue("Bearer",key);
                req.Content=new StringContent(JsonSerializer.Serialize(new {
                    personalizations=new[]{new {to=new[]{new {email=dest}}}},
                    from=new{email=from},subject,content=new[]{new {type="text/plain",value=body}}}),Encoding.UTF8,"application/json");
                using var response=await clients.CreateClient().SendAsync(req,ct);
                httpStatus=(int)response.StatusCode;
                if(!response.IsSuccessStatusCode)throw new HttpRequestException($"Email delivery provider returned HTTP {httpStatus}.");
                providerId=response.Headers.TryGetValues("X-Message-Id",out var ids)?ids.FirstOrDefault():null;
            }
            else if(channel=="SMS")
            {
                var sid=config["Notifications:Twilio:AccountSid"];
                var secret=config["Notifications:Twilio:AuthToken"];
                var from=config["Notifications:Twilio:FromPhone"];
                if(string.IsNullOrWhiteSpace(sid)||string.IsNullOrWhiteSpace(secret)||string.IsNullOrWhiteSpace(from)
                    ||string.IsNullOrWhiteSpace(dest)||!dest.StartsWith('+'))
                    throw new InvalidOperationException("Twilio SMS delivery is not configured or recipient number is invalid.");
                using var req=new HttpRequestMessage(HttpMethod.Post,
                    $"https://api.twilio.com/2010-04-01/Accounts/{Uri.EscapeDataString(sid)}/Messages.json");
                req.Headers.Authorization=new AuthenticationHeaderValue("Basic",
                    Convert.ToBase64String(Encoding.UTF8.GetBytes(sid+":"+secret)));
                req.Content=new FormUrlEncodedContent(new Dictionary<string,string>{["To"]=dest,["From"]=from,["Body"]=body});
                using var response=await clients.CreateClient().SendAsync(req,ct);
                httpStatus=(int)response.StatusCode;
                if(!response.IsSuccessStatusCode)throw new HttpRequestException($"SMS delivery provider returned HTTP {httpStatus}.");
                using var receipt=JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
                providerId=receipt.RootElement.TryGetProperty("sid",out var sidVal)?sidVal.GetString():null;
            }
            else if(channel!="InApp")throw new InvalidOperationException("Unsupported notification channel.");
            await db.ProcedureAsync("notify.usp_RecordDelivery",new[]{SqlDatabase.G("NotificationId",id),
                SqlDatabase.S("Outcome",channel=="InApp"?"Delivered":"Accepted"),
                SqlDatabase.S("ProviderMessageId",providerId),new SqlArgument("HttpStatus",httpStatus,SqlDbType.Int)},ct);
        }
        catch(OperationCanceledException) when(ct.IsCancellationRequested){throw;}
        catch(Exception ex)
        {
            logger.LogWarning("Notification {Id} provider attempt failed ({Type}); will retry",id,ex.GetType().Name);
            try{await db.ProcedureAsync("notify.usp_RecordDelivery",new[]{
                SqlDatabase.G("NotificationId",id),SqlDatabase.S("Outcome","Failed"),
                SqlDatabase.S("Error",ex.GetType().Name)},ct);}
            catch(Exception recordError){logger.LogError(recordError,"Could not record failed notification {Id}",id);}
        }
    }
    private async Task ResumeNodesAsync(SqlDatabase db,CancellationToken ct)
    {
        var nodes=(await db.QueryAsync(@"SELECT TOP(30) sn.InstanceId,sn.NodeId FROM work.SystemNotifications sn
JOIN notify.Outbox o ON o.NotificationId=sn.NotificationId
WHERE sn.ResumedAt IS NULL AND o.State IN('Accepted','Delivered') ORDER BY o.NotificationId",[],ct)).First;
        foreach(var row in nodes)
        {
            try{await db.ProcedureAsync("work.usp_ResumeSystemNode",new[]{
                SqlDatabase.G("InstanceId",Convert.ToInt64(row["InstanceId"])),
                SqlDatabase.G("NodeId",Convert.ToInt64(row["NodeId"]))},ct);}
            catch(Exception ex){logger.LogWarning(ex,"Notification node continuation failed");}
        }
    }
}
