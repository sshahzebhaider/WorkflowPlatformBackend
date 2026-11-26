using System.Diagnostics;
using System.Security.Cryptography;
using WorkflowPlatform.Api.Data;

namespace WorkflowPlatform.Api.Services;

/// <summary>Fail-closed malware scan using an operator-installed ClamAV binary.
/// A file cannot become downloadable until the result is clean and its stored SHA matches.</summary>
public sealed class AttachmentScanWorker(IServiceScopeFactory scopeFactory,IConfiguration config,
    IWebHostEnvironment host,ILogger<AttachmentScanWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken token)
    {
        if(!string.Equals(config["Files:ScanMode"],"ClamAV",StringComparison.OrdinalIgnoreCase))return;
        var root=Path.GetFullPath(Path.Combine(host.ContentRootPath,config["Files:Root"]??"App_Data/private-uploads"));
        var executable=config["Files:ClamScanExecutable"]??"clamscan";
        while(!token.IsCancellationRequested)
        {
            try
            {
                using var scope=scopeFactory.CreateScope();
                var db=scope.ServiceProvider.GetRequiredService<SqlDatabase>();
                var docs=(await db.QueryAsync(@"SELECT TOP(10) DocumentId,StorageKey,Sha256 FROM files.Documents
WHERE ScanStatus='Pending' AND IsDeleted=0 ORDER BY UploadedAt,DocumentId",[],token)).First;
                foreach(var doc in docs)
                {
                    var id=Convert.ToInt64(doc["DocumentId"]);
                    try
                    {
                        var path=Path.GetFullPath(Path.Combine(root,(doc["StorageKey"]?.ToString()??"").Replace('/',Path.DirectorySeparatorChar)));
                        if(!path.StartsWith(root+Path.DirectorySeparatorChar,StringComparison.Ordinal)||!File.Exists(path))
                            throw new IOException("Attachment path is missing or invalid.");
                        if(doc["Sha256"] is not string checksum)throw new IOException("Attachment checksum is missing.");
                        await using(var stream=File.OpenRead(path))
                        {
                            var actual=await SHA256.HashDataAsync(stream,token);
                            if(!CryptographicOperations.FixedTimeEquals(actual,Convert.FromBase64String(checksum)))
                                throw new IOException("Attachment integrity check failed.");
                        }
                        using var process=new Process();
                        process.StartInfo=new ProcessStartInfo(executable){UseShellExecute=false,CreateNoWindow=true};
                        process.StartInfo.ArgumentList.Add("--no-summary");
                        process.StartInfo.ArgumentList.Add("--");
                        process.StartInfo.ArgumentList.Add(path);
                        if(!process.Start())throw new IOException("ClamAV could not start.");
                        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(token);
                        timeout.CancelAfter(TimeSpan.FromMinutes(2));
                        try { await process.WaitForExitAsync(timeout.Token); }
                        catch(OperationCanceledException) { if(!process.HasExited)process.Kill(entireProcessTree:true); throw; }
                        if(process.ExitCode==0 || process.ExitCode==1)
                        {
                            await db.ProcedureAsync("files.usp_RecordScanResult",new[]{
                                SqlDatabase.G("DocumentId",id),new WorkflowPlatform.Api.Data.SqlArgument("Clean",process.ExitCode==0,System.Data.SqlDbType.Bit)},token);
                            logger.LogInformation("Attachment {DocumentId} malware scan outcome {Outcome}",id,process.ExitCode==0?"Clean":"Rejected");
                        }
                        else throw new IOException($"ClamAV scanner returned exit code {process.ExitCode}.");
                    }
                    catch(OperationCanceledException) when(token.IsCancellationRequested) { throw; }
                    catch(Exception ex) { logger.LogError(ex,"Attachment {DocumentId} not cleared; still pending",id); }
                }
            }
            catch(OperationCanceledException) when(token.IsCancellationRequested) { break; }
            catch(Exception ex) { logger.LogError(ex,"Attachment malware scan pump failed"); }
            try { await Task.Delay(TimeSpan.FromSeconds(20),token); }
            catch(OperationCanceledException) when(token.IsCancellationRequested) { break; }
        }
    }
}
