using System.Data;
using System.Security.Cryptography;
using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;
using WorkflowPlatform.Api.Services;

namespace WorkflowPlatform.Api.Api;

public static class AttachmentEndpoints
{
    private static readonly HashSet<string> Extensions = new(StringComparer.OrdinalIgnoreCase){".pdf",".png",".jpg",".jpeg",".docx"};
    public static void MapAttachmentEndpoints(this RouteGroupBuilder api)
    {
        // Intake uploads are staged and malware-scanned before a case exists. Ownership and
        // published form membership are verified again in work.usp_CreateCase under SQL locks.
        api.MapPost("/projects/{projectId:long}/case-types/{caseTypeId:long}/attachments/stage",async(
            long projectId,long caseTypeId,HttpContext ctx,ActorResolver actors,ProjectAccess access,
            SqlDatabase db,IConfiguration config,IWebHostEnvironment host,PrecaseAttachmentScanner scanner,CancellationToken ct)=>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await access.RequireAsync(actor,projectId,"cases.create",ct);
            if(!ctx.Request.HasFormContentType)throw new ArgumentException("multipart/form-data required.");
            var form=await ctx.Request.ReadFormAsync(ct);
            var fieldKey=form["fieldKey"].ToString();
            if(string.IsNullOrWhiteSpace(fieldKey)||fieldKey.Length>100)
                throw new ArgumentException("Published attachment field required.");
            var rows=(await db.QueryAsync(@"SELECT TOP(1) f.FormVersionId,f.FieldKey FROM core.CaseTypes t
JOIN core.CaseTypeVersions ctv ON ctv.CaseTypeVersionId=t.LiveVersionId
JOIN forms.VersionFields f ON f.FormVersionId=ctv.IntakeFormVersionId
WHERE t.CaseTypeId=@type AND t.ProjectId=@project AND t.IsActive=1
AND f.FieldType='attachment' AND f.FieldKey=@field",
                new[]{SqlDatabase.G("type",caseTypeId),SqlDatabase.G("project",projectId),SqlDatabase.S("field",fieldKey)},ct)).First;
            if(rows.Count==0)throw new ArgumentException("No attachment field found in the published intake form.");
            var file=form.Files.GetFile("file")??throw new ArgumentException("Missing file.");
            var max=Math.Min(20*1024*1024,config.GetValue<long?>("Files:MaxBytes")??20*1024*1024);
            if(file.Length<=0||file.Length>max)throw new ArgumentException("File size exceeds the allowed limit.");
            var name=Path.GetFileName(file.FileName);
            if(string.IsNullOrWhiteSpace(name)||name.Length>260||!Extensions.Contains(Path.GetExtension(name)))
                throw new ArgumentException("File type is not supported.");
            var version=Convert.ToInt64(rows[0]["FormVersionId"]);
            var root=Path.GetFullPath(Path.Combine(host.ContentRootPath,config["Files:Root"]??"App_Data/private-uploads"));
            var key=$"staged/{projectId}/{Convert.ToHexString(RandomNumberGenerator.GetBytes(20))}";
            var target=Path.GetFullPath(Path.Combine(root,key.Replace('/',Path.DirectorySeparatorChar)));
            if(!target.StartsWith(root+Path.DirectorySeparatorChar,StringComparison.Ordinal))
                throw new InvalidOperationException("Invalid storage path.");
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            try
            {
                await using(var output=new FileStream(target,FileMode.CreateNew,FileAccess.Write,FileShare.None))
                    await file.CopyToAsync(output,ct);
                await scanner.ScanAsync(target,ct);
                byte[] digest;
                await using(var stream=File.OpenRead(target))digest=await SHA256.HashDataAsync(stream,ct);
                var result=await db.ProcedureAsync("files.usp_CreateStagedDocument",new[]{
                    SqlDatabase.G("project",projectId),SqlDatabase.G("type",caseTypeId),
                    SqlDatabase.G("version",version),SqlDatabase.G("actor",actor.UserId),
                    SqlDatabase.S("field",fieldKey),SqlDatabase.S("key",key),
                    SqlDatabase.S("name",name),SqlDatabase.S("mime",file.ContentType),
                    new SqlArgument("size",file.Length,SqlDbType.BigInt),
                    new SqlArgument("digest",digest,SqlDbType.VarBinary,32)},ct);
                return Results.Ok(new {stageId=result.First[0]["StageId"],fileName=name,size=file.Length,
                    scanStatus="Clean",expiresInMinutes=120});
            }
            catch {if(File.Exists(target))File.Delete(target);throw;}
        }).DisableAntiforgery();
        api.MapPost("/projects/{projectId:long}/cases/{caseId:long}/attachments",async(
            long projectId,long caseId,HttpContext ctx,ActorResolver actors,ProjectAccess access,SqlDatabase db,
            IConfiguration config,IWebHostEnvironment host,CancellationToken ct)=>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            // Case membership is checked here; files.usp_RegisterDocument separately enforces
            // cases.create or cases.manage so a reviewer can attach documents to an assigned case.
            // The detail procedure enforces case membership and project isolation.
            await db.ProcedureAsync("work.usp_GetCaseDetails", new[] {SqlDatabase.G("ActorUserId",actor.UserId),
                SqlDatabase.G("ProjectId",projectId),SqlDatabase.G("CaseId",caseId)},ct);
            if (!ctx.Request.HasFormContentType)throw new ArgumentException("Upload must use multipart/form-data.");
            var data=await ctx.Request.ReadFormAsync(ct);
            var file=data.Files.GetFile("file")??throw new ArgumentException("Missing file.");
            var max=Math.Clamp(config.GetValue<long?>("Files:MaxBytes")??20*1024*1024,1,20*1024*1024);
            if(file.Length<=0||file.Length>max)throw new ArgumentException("File must be 1 byte to 20 MB.");
            var safeName=Path.GetFileName(file.FileName);
            if (safeName.Length==0||safeName.Length>260||!Extensions.Contains(Path.GetExtension(safeName)))
                throw new ArgumentException("Unsupported filename or extension.");
            var root=Path.GetFullPath(Path.Combine(host.ContentRootPath,config["Files:Root"]??"App_Data/private-uploads"));
            var key=$"{projectId}/{caseId}/{Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(16))}";
            var target=Path.GetFullPath(Path.Combine(root,key.Replace('/',Path.DirectorySeparatorChar)));
            if(!target.StartsWith(root+Path.DirectorySeparatorChar,StringComparison.Ordinal))throw new InvalidOperationException("Invalid file path.");
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            byte[] sha;
            try
            {
                await using(var destination=new FileStream(target,FileMode.CreateNew,FileAccess.Write,FileShare.None))
                await using(var input=file.OpenReadStream())
                {
                    using var hash=IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
                    var chunk=new byte[8192]; int count; long length=0;
                    while((count=await input.ReadAsync(chunk,ct))>0)
                    {
                        length+=count;
                        if(length>max)throw new ArgumentException("File exceeded maximum upload size.");
                        await destination.WriteAsync(chunk.AsMemory(0,count),ct);
                        hash.AppendData(chunk,0,count);
                    }
                    sha=hash.GetHashAndReset();
                }
                var args=new List<SqlArgument>{SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("ProjectId",projectId),
                    SqlDatabase.G("CaseId",caseId),SqlDatabase.S("StorageKey",key),SqlDatabase.S("OriginalFileName",safeName),
                    SqlDatabase.S("MimeType",file.ContentType),new("FileSizeBytes",file.Length,SqlDbType.BigInt),
                    new("Sha256",sha,SqlDbType.VarBinary,32),new("DocumentId",null,SqlDbType.BigInt,IsOutput:true)};
                if(long.TryParse(data["taskId"],out var taskId))args.Add(SqlDatabase.G("TaskId",taskId));
                if(long.TryParse(data["formVersionId"],out var formId))args.Add(SqlDatabase.G("FormVersionId",formId));
                if(!string.IsNullOrWhiteSpace(data["fieldKey"]))args.Add(SqlDatabase.S("FieldKey",data["fieldKey"]));
                var result=await db.ProcedureAsync("files.usp_RegisterDocument",args,ct);
                return Results.Ok(new {documentId=result.Outputs["DocumentId"],fileName=safeName,scanStatus="Pending"});
            }
            catch { if(File.Exists(target))File.Delete(target); throw; }
        }).DisableAntiforgery(); // Bearer-only API; no auth cookie is used.
        api.MapGet("/projects/{projectId:long}/cases/{caseId:long}/attachments/{documentId:long}",async(
            long projectId,long caseId,long documentId,HttpContext ctx,ActorResolver actors,SqlDatabase db,
            IConfiguration config,IWebHostEnvironment host,CancellationToken ct)=>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await db.ProcedureAsync("work.usp_GetCaseDetails",new[] {SqlDatabase.G("ActorUserId",actor.UserId),
                SqlDatabase.G("ProjectId",projectId),SqlDatabase.G("CaseId",caseId)},ct);
            var doc=(await db.QueryAsync(@"
SELECT StorageKey,OriginalFileName,MimeType,ScanStatus,Sha256 FROM files.Documents
WHERE DocumentId=@doc AND ProjectId=@project AND CaseId=@case AND IsDeleted=0",
                new[]{SqlDatabase.G("doc",documentId),SqlDatabase.G("project",projectId),SqlDatabase.G("case",caseId)},ct)).First.FirstOrDefault();
            if(doc is null)return Results.NotFound();
            if(!string.Equals(doc["ScanStatus"]?.ToString(),"Clean",StringComparison.OrdinalIgnoreCase))
                return Results.Problem(statusCode:423,title:"Attachment is not cleared for download",
                    detail:"Files must pass your organization's malware scanning process.");
            var root=Path.GetFullPath(Path.Combine(host.ContentRootPath,config["Files:Root"]??"App_Data/private-uploads"));
            var path=Path.GetFullPath(Path.Combine(root,doc["StorageKey"]!.ToString()!.Replace('/',Path.DirectorySeparatorChar)));
            if(!path.StartsWith(root+Path.DirectorySeparatorChar,StringComparison.Ordinal))return Results.BadRequest();
            if(!File.Exists(path))return Results.NotFound();
            var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
            try
            {
                var digest=await SHA256.HashDataAsync(stream,ct);
                if(doc["Sha256"] is not string expected || !CryptographicOperations.FixedTimeEquals(digest,Convert.FromBase64String(expected)))
                { await stream.DisposeAsync(); return Results.Problem(statusCode:423,title:"Attachment integrity verification failed"); }
                stream.Position=0;
                return Results.File(stream,"application/octet-stream",fileDownloadName: doc["OriginalFileName"]!.ToString(),enableRangeProcessing:false);
            }
            catch { await stream.DisposeAsync(); throw; }
        });
    }
}
