using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using WorkflowPlatform.Api.Data;

namespace WorkflowPlatform.Api.Services;

public sealed record PublishedLodgementOperation(long OperationId,long CaseTypeVersionId);
public sealed record LodgementPreview(long PreviewId,string PreviewToken,int HttpStatus,
    List<LodgementResponseField> Fields,bool Truncated,Dictionary<string,JsonElement> IntakeValues,List<LodgementPreview>? Records=null);
public sealed record LodgementResponseField(string Path,string Value);

/// <summary>
/// Performs the optional Case Type REST lookup BEFORE the intake form. The API
/// is never executed from untrusted browser-defined URLs or request templates.
/// A server-persisted, expiring opaque receipt carries the approved response
/// into case creation without a second external request.
/// </summary>
public sealed class LodgementIntegration(SqlDatabase db,OperationTester tester)
{
    public async Task<PublishedLodgementOperation?> GetOperationAsync(long projectId,long caseTypeId,CancellationToken ct)
    {
        var rows=(await db.QueryAsync(@"
SELECT v.CaseTypeVersionId,v.PublishedConfigJson
FROM core.CaseTypes t JOIN core.CaseTypeVersions v ON v.CaseTypeVersionId=t.LiveVersionId
WHERE t.ProjectId=@project AND t.CaseTypeId=@type AND t.IsActive=1",
            new[]{SqlDatabase.G("project",projectId),SqlDatabase.G("type",caseTypeId)},ct)).First;
        if(rows.Count==0)throw new ArgumentException("Select a published Case Type before lodging.");
        using var config=JsonDocument.Parse((string)rows[0]["PublishedConfigJson"]!);
        if(!config.RootElement.TryGetProperty("lodgementIntegration",out var setup) || setup.ValueKind==JsonValueKind.Null)
            return null;
        if(setup.ValueKind!=JsonValueKind.Object || !setup.TryGetProperty("operationId",out var op) ||
            !long.TryParse(op.ToString(),out var operationId) || operationId<=0)
            throw new ArgumentException("The published Case Type has an invalid data-source operation.");
        var approved=await db.ScalarAsync(@"
SELECT COUNT_BIG(*) FROM integration.Operations o
JOIN integration.DataSources s ON s.DataSourceId=o.DataSourceId
JOIN integration.ProjectDataSources p ON p.DataSourceId=s.DataSourceId AND p.ProjectId=@project
WHERE o.OperationId=@operation AND o.IsActive=1 AND s.IsActive=1 AND s.Kind='REST'",
            new[]{SqlDatabase.G("project",projectId),SqlDatabase.G("operation",operationId)},ct);
        if(Convert.ToInt64(approved??0L)!=1)
            throw new ArgumentException("The Case Type's data-source operation is no longer approved for this project.");
        // Keep the namespace used for the read-only API result distinct from
        // user-editable intake keys, rather than discovering a collision at submit.
        var conflict=await db.ScalarAsync(@"
SELECT COUNT_BIG(*) FROM core.CaseTypes t
JOIN core.CaseTypeVersions v ON v.CaseTypeVersionId=t.LiveVersionId
JOIN forms.VersionFields f ON f.FormVersionId=v.IntakeFormVersionId
WHERE t.ProjectId=@project AND t.CaseTypeId=@type AND f.FieldKey='api_response'",
            new[]{SqlDatabase.G("project",projectId),SqlDatabase.G("type",caseTypeId)},ct);
        if(Convert.ToInt64(conflict??0L)>0)
            throw new ArgumentException("The intake form uses the reserved field key 'api_response'. Rename that field before using an external lookup.");
        return new PublishedLodgementOperation(operationId,Convert.ToInt64(rows[0]["CaseTypeVersionId"]!));
    }

    public async Task<LodgementPreview> PreviewAsync(long projectId,long caseTypeId,long actorId,
        Dictionary<string,JsonElement> inputs,CancellationToken ct)
    {
        var published=await GetOperationAsync(projectId,caseTypeId,ct)
            ?? throw new ArgumentException("This Case Type has no pre-intake data source configured.");
        if(inputs.Count>100)throw new ArgumentException("Too many data-source inputs.");
        var response=await tester.RunAsync(published.OperationId,inputs,ct,projectId:projectId,readOnly:true,selectRecords:true);
        // The Platform Admin can explicitly choose response mappings. Without
        // mappings, expose the structured JSON response as read-only lookup data.
        // A successful lookup with no mapped matches is valid. Preserve the empty
        // approved projection and receipt; never fall back to unapproved raw fields.
        var data=ExpandJsonString(response.HasResponseMappings
            ? JsonSerializer.SerializeToElement(response.Mapped)
            : response.Body);
        var intakeFields=(await db.QueryAsync(@"SELECT f.FieldKey,f.FieldType FROM core.CaseTypeVersions v JOIN forms.VersionFields f ON f.FormVersionId=v.IntakeFormVersionId WHERE v.CaseTypeVersionId=@version",new[]{SqlDatabase.G("version",published.CaseTypeVersionId)},ct)).First;
        if(response.LodgementRecords is {Count: >1} records)
        {
            // Every choice gets a server-issued receipt bound to the same actor, project and case type.
            // Only the selected projection is attached to the resulting case.
            if(records.Sum(row=>Encoding.UTF8.GetByteCount(row.GetRawText()))>131072)
                throw new ArgumentException("The record projections are too large. Configure smaller response mappings.");
            var choices=new List<LodgementPreview>();
            foreach(var row in records)choices.Add(await SaveAsync(row));
            return choices[0] with { Records=choices };
        }
        return await SaveAsync(response.LodgementRecords is {Count: 1} single ? single[0] : data);
        async Task<LodgementPreview> SaveAsync(JsonElement recordData)
        {
        if(recordData.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null)
            recordData=JsonSerializer.SerializeToElement(new Dictionary<string,object?>());
        var wrapped=JsonSerializer.Serialize(new Dictionary<string,JsonElement>{["api_response"]=recordData});
        if(Encoding.UTF8.GetByteCount(wrapped)>131072)
            throw new ArgumentException("The API response is too large to attach to a case. Configure a smaller response mapping in Data Connections.");
        var fields=ToFields(recordData);
        // Empty approved projections deliberately produce an empty display and intake form.
        var display=JsonSerializer.Serialize(fields);
        var secret=Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        var digest=SHA256.HashData(Encoding.UTF8.GetBytes(secret));
        var saved=await db.ProcedureAsync("integration.usp_SaveLodgementPreview",new[]{
            SqlDatabase.G("ActorUserId",actorId),SqlDatabase.G("ProjectId",projectId),
            SqlDatabase.G("CaseTypeId",caseTypeId),SqlDatabase.G("CaseTypeVersionId",published.CaseTypeVersionId),
            SqlDatabase.G("OperationId",published.OperationId),
            new SqlArgument("TokenHash",digest,SqlDbType.VarBinary,32),
            SqlDatabase.S("MappedFieldsJson",wrapped),SqlDatabase.S("DisplayJson",display),
            new SqlArgument("PreviewId",null,SqlDbType.BigInt,IsOutput:true)
        },ct);
        var id=Convert.ToInt64(saved.Outputs["PreviewId"]!);

        var intakeValues=new Dictionary<string,JsonElement>(StringComparer.Ordinal);
        foreach(var field in intakeFields)
        {
            var key=Convert.ToString(field["FieldKey"])!;
            var kind=Convert.ToString(field["FieldType"]);
            if(kind=="attachment" || new[]{"api_response","__proto__","constructor","prototype"}.Contains(key,StringComparer.OrdinalIgnoreCase)) continue;
            var matches=new List<JsonElement>();
            string Normalize(string value)=>new string(value.Where(c=>char.IsAsciiLetter(c)).ToArray()).ToLowerInvariant();
            bool Same(string name,bool normalized)=> (normalized ? Normalize(name) : name).Equals(normalized ? Normalize(key) : key,StringComparison.OrdinalIgnoreCase);
            if(recordData.ValueKind==JsonValueKind.Object)
            {
                foreach(var prop in recordData.EnumerateObject())
                    if(Same(prop.Name,false)) matches.Add(prop.Value);
                // Exact top-level/mapped keys take precedence. For nested objects, only an
                // unambiguous matching property is safe; do not choose among array records.
                if(matches.Count==0)
                {
                    void Walk(JsonElement obj,int depth,bool normalized)
                    {
                        if(depth>8 || obj.ValueKind!=JsonValueKind.Object || matches.Count>1) return;
                        foreach(var prop in obj.EnumerateObject())
                        {
                            if(Same(prop.Name,normalized)) matches.Add(prop.Value);
                            var nested=ExpandJsonString(prop.Value);
                            if(nested.ValueKind==JsonValueKind.Object) Walk(nested,depth+1,normalized);
                        }
                    }
                    Walk(recordData,0,false);
                    if(matches.Count==0 && !response.HasResponseMappings && Normalize(key).Length>0 && intakeFields.Count(f=>Same(Convert.ToString(f["FieldKey"]) ?? "",true))==1) Walk(recordData,0,true);
                }
            }
            if(matches.Count!=1) continue;
            var item=matches[0];
            if(item.ValueKind is JsonValueKind.String or JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False) intakeValues[key]=item.Clone();
        }
        return new LodgementPreview(id,secret,response.Status,fields,fields.Count>=160,intakeValues);
        }
    }

    public static byte[] HashPreviewToken(string? token)
    {
        if(string.IsNullOrWhiteSpace(token) || token.Length!=64 ||
            !token.All(c=>char.IsAsciiHexDigit(c)))
            throw new ArgumentException("Verify the data source again before creating the case.");
        return SHA256.HashData(Encoding.UTF8.GetBytes(token));
    }

    // Some approved APIs return a JSON object/array encoded inside a JSON string.
    // Interpret only well-formed structured JSON; preserve ordinary text as text.
    // Keep a hard limit so huge string payloads cannot be recursively expanded.
    internal static JsonElement ExpandJsonString(JsonElement item)
    {
        if(item.ValueKind!=JsonValueKind.String)return item;
        var raw=item.GetString();
        if(string.IsNullOrWhiteSpace(raw) || raw.Length>131072)return item;
        var value=raw.Trim();
        if(!((value.StartsWith('{')&&value.EndsWith('}')) ||
             (value.StartsWith('[')&&value.EndsWith(']'))))return item;
        try
        {
            using var parsed=JsonDocument.Parse(value);
            if(parsed.RootElement.ValueKind is JsonValueKind.Object or JsonValueKind.Array)
                return parsed.RootElement.Clone();
        }
        catch(JsonException) { /* An ordinary text string: do not treat as structured JSON. */ }
        return item;
    }

    // Keep dynamic response paths (including arrays) readable rather than
    // requiring Platform Admins to define every field in advance.
    public static List<LodgementResponseField> ToFields(JsonElement root,int max=160)
    {
        var results=new List<LodgementResponseField>();
        void Walk(JsonElement item,string path,int depth)
        {
            if(results.Count>=max)return;
            item=ExpandJsonString(item);
            if(depth>10){results.Add(new(path,"[nested data]"));return;}
            switch(item.ValueKind)
            {
                case JsonValueKind.Object:
                    foreach(var prop in item.EnumerateObject())
                    {
                        if(results.Count>=max)break;
                        Walk(prop.Value,string.IsNullOrEmpty(path)?prop.Name:$"{path}.{prop.Name}",depth+1);
                    }
                    break;
                case JsonValueKind.Array:
                    var index=0;
                    foreach(var child in item.EnumerateArray())
                    {
                        if(results.Count>=max)break;
                        Walk(child,$"{path}[{index++}]",depth+1);
                    }
                    if(index==0)results.Add(new(path,"[]"));
                    break;
                default:
                    var value=item.ValueKind switch{
                        JsonValueKind.Null=>"—",
                        JsonValueKind.String=>item.GetString()??"",
                        _=>item.ToString()
                    };
                    if(value.Length>240)value=value[..240]+"…";
                    results.Add(new(string.IsNullOrEmpty(path)?"Value":path,value));
                    break;
            }
        }
        Walk(root,"",0);
        return results;
    }
}
