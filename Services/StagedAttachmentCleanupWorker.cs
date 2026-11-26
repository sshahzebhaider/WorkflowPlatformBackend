using System.Text.RegularExpressions;
using WorkflowPlatform.Api.Data;

namespace WorkflowPlatform.Api.Services;

public sealed class StagedAttachmentCleanupWorker(SqlDatabase db, IConfiguration config,
    IWebHostEnvironment host, ILogger<StagedAttachmentCleanupWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        var root=Path.GetFullPath(Path.Combine(host.ContentRootPath,config["Files:Root"]??"App_Data/private-uploads"));
        while(!ct.IsCancellationRequested)
        {
            try
            {
                var rows=(await db.QueryAsync(@"SELECT TOP(100) StageId,StorageKey FROM files.StagedDocuments
WHERE ConsumedCaseId IS NULL AND ExpiresAt<=DATEADD(MINUTE,-10,SYSUTCDATETIME()) ORDER BY ExpiresAt,StageId",[],ct)).First;
                foreach(var row in rows)
                {
                    var id=Convert.ToInt64(row["StageId"]);
                    try
                    {
                        var key=row["StorageKey"]?.ToString()??"";
                        if(!Regex.IsMatch(key,@"^staged/[0-9]+/[0-9A-F]{40}$",RegexOptions.CultureInvariant))
                            throw new IOException("Invalid generated staged file key.");
                        var path=Path.GetFullPath(Path.Combine(root,key.Replace('/',Path.DirectorySeparatorChar)));
                        if(!path.StartsWith(root+Path.DirectorySeparatorChar,StringComparison.Ordinal)) throw new IOException("Invalid staged path.");
                        File.Delete(path);
                        await db.ProcedureAsync("files.usp_DeleteExpiredStage",new[]{SqlDatabase.G("StageId",id)},ct);
                    }
                    catch(OperationCanceledException) when(ct.IsCancellationRequested) { throw; }
                    catch(Exception ex) { logger.LogWarning(ex,"Expired attachment {StageId} cleanup failed",id); }
                }
            }
            catch(OperationCanceledException) when(ct.IsCancellationRequested) { break; }
            catch(Exception ex) { logger.LogError(ex,"Staged attachment cleanup failed"); }
            try { await Task.Delay(TimeSpan.FromMinutes(5),ct); }
            catch(OperationCanceledException) when(ct.IsCancellationRequested) { break; }
        }
    }
}
