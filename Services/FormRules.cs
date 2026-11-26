using System.Text.Json;
using System.Globalization;
using System.Text.RegularExpressions;
using WorkflowPlatform.Api.Data;

namespace WorkflowPlatform.Api.Services;

public sealed class FormRules(SqlDatabase db)
{
    public async Task ValidateIntakeAsync(long projectId, long caseTypeId, JsonElement intake, CancellationToken ct)
    {
        if (intake.ValueKind != JsonValueKind.Object) throw new ArgumentException("intakeJson must be a JSON object.");
        var result = await db.QueryAsync(@"
SELECT f.FieldKey,f.FieldType,f.IsRequired,f.RegexPattern,f.RegexMessage
FROM core.CaseTypes ct JOIN core.CaseTypeVersions ctv ON ctv.CaseTypeVersionId=ct.LiveVersionId
JOIN forms.VersionFields f ON f.FormVersionId=ctv.IntakeFormVersionId
WHERE ct.CaseTypeId=@type AND ct.ProjectId=@project AND ct.IsActive=1",
            new[] { SqlDatabase.G("type",caseTypeId),SqlDatabase.G("project",projectId) },ct);
        if (result.First.Count == 0)
        {
            var exists=await db.ScalarAsync(@"SELECT COUNT(*) FROM core.CaseTypes t JOIN core.CaseTypeVersions v
ON v.CaseTypeVersionId=t.LiveVersionId WHERE t.ProjectId=@project AND t.CaseTypeId=@type AND t.IsActive=1",
                new[]{SqlDatabase.G("project",projectId),SqlDatabase.G("type",caseTypeId)},ct);
            if (Convert.ToInt32(exists)==0)throw new ArgumentException("Published case type not found.");
        }
        ValidateFields(result.First, intake);
        if(result.First.Count>0)
        {
            var version=(await db.ScalarAsync(@"SELECT v.IntakeFormVersionId FROM core.CaseTypes t
JOIN core.CaseTypeVersions v ON v.CaseTypeVersionId=t.LiveVersionId
WHERE t.ProjectId=@project AND t.CaseTypeId=@type",
                new[]{SqlDatabase.G("project",projectId),SqlDatabase.G("type",caseTypeId)},ct));
            if(version is not null)await ValidateSelectValuesAsync(Convert.ToInt64(version),intake,ct);
        }
    }
    public async Task ValidateStepAnswersAsync(long taskId, JsonElement byForm, CancellationToken ct)
    {
        if (byForm.ValueKind != JsonValueKind.Object) throw new ArgumentException("answersByFormJson must be an object keyed by form version ID.");
        var result = await db.QueryAsync(@"
SELECT nf.FormVersionId,f.FieldKey,f.FieldType,f.IsRequired,f.RegexPattern,f.RegexMessage
FROM work.Tasks t JOIN flow.NodeForms nf ON nf.NodeId=t.NodeId
JOIN forms.VersionFields f ON f.FormVersionId=nf.FormVersionId WHERE t.TaskId=@task",
            new[] { SqlDatabase.G("task",taskId) },ct);
        foreach (var group in result.First.GroupBy(r=>(long)r["FormVersionId"]!))
        {
            if (!byForm.TryGetProperty(group.Key.ToString(),out var answers))
            {
                if (group.Any(f=>Convert.ToBoolean(f["IsRequired"])))
                    throw new ArgumentException($"Required form {group.Key} has not been completed.");
                continue;
            }
            ValidateFields(group.ToList(),answers);
            await ValidateSelectValuesAsync(group.Key,answers,ct);
        }
        foreach(var submitted in byForm.EnumerateObject())
            if (!long.TryParse(submitted.Name,out var id) || !result.First.Any(x=>Equals(x["FormVersionId"],id)))
                throw new ArgumentException("An unassigned form version was supplied.");

        // Attachment IDs are never accepted merely because the submitted value is a JSON array.
        // Every referenced file must belong to this case, to the current task/field, and exist
        // as a registered document. Bytes are gated separately by malware scanning for download.
        var fileFields=result.First.Where(f=>string.Equals(f["FieldType"]?.ToString(),"attachment",StringComparison.OrdinalIgnoreCase)).ToList();
        if(fileFields.Count>0)
        {
            var docs=(await db.QueryAsync(@"SELECT d.DocumentId,d.FieldKey,d.TaskId FROM files.Documents d
JOIN work.Instances inst ON inst.CaseId=d.CaseId
JOIN work.Tasks t ON t.InstanceId=inst.InstanceId
WHERE t.TaskId=@task AND d.IsDeleted=0 AND d.TaskId=@task",
                new[]{SqlDatabase.G("task",taskId)},ct)).First;
            foreach(var field in fileFields)
            {
                var version=(long)field["FormVersionId"]!;
                var key=field["FieldKey"]!.ToString()!;
                if(!byForm.TryGetProperty(version.ToString(),out var values) ||
                   !values.TryGetProperty(key,out var references) ||
                   references.ValueKind!=JsonValueKind.Array) continue;
                foreach(var reference in references.EnumerateArray())
                {
                    if(reference.ValueKind is not (JsonValueKind.String or JsonValueKind.Number) || !long.TryParse(reference.ToString(),out var fileId)
                       || !docs.Any(d=>Equals(d["DocumentId"],fileId) &&
                            string.Equals(d["FieldKey"]?.ToString(),key,StringComparison.Ordinal)))
                        throw new ArgumentException($"An attachment for field '{key}' does not belong to this task.");
                }
            }
        }
    }
    private async Task ValidateSelectValuesAsync(long formVersionId,JsonElement values,CancellationToken ct)
    {
        // Values must reference active items from the pinned lookup version's configured list,
        // including parent-child relationships. The client dropdown is not a security boundary.
        var rows=(await db.QueryAsync(@"SELECT f.FieldKey,f.ParentFieldKey,i.ItemId,i.Code,i.ParentItemId,
 parent.Code AS ParentCode
FROM forms.VersionFields f LEFT JOIN lookup.Items i ON i.ListId=f.LookupListId AND i.IsActive=1
LEFT JOIN lookup.Items parent ON parent.ItemId=i.ParentItemId
WHERE f.FormVersionId=@version AND f.FieldType='select'",new[]{SqlDatabase.G("version",formVersionId)},ct)).First;
        foreach(var group in rows.GroupBy(r=>r["FieldKey"]?.ToString()))
        {
            var key=group.Key;
            if(string.IsNullOrWhiteSpace(key)||!values.TryGetProperty(key,out var selected) || selected.ValueKind==JsonValueKind.Null)continue;
            var selectedText=selected.ToString();
            var item=group.FirstOrDefault(row=>row["ItemId"] is not null &&
                (row["ItemId"]?.ToString()==selectedText || string.Equals(row["Code"]?.ToString(),selectedText,StringComparison.Ordinal)));
            if(item is null)throw new ArgumentException($"Dropdown '{key}' contains a value that is not in its active lookup.");
            var parentField=item["ParentFieldKey"]?.ToString();
            if(!string.IsNullOrWhiteSpace(parentField))
            {
                if(!values.TryGetProperty(parentField,out var parentSelected) || parentSelected.ValueKind==JsonValueKind.Null)
                    throw new ArgumentException($"Dropdown '{key}' requires its parent value.");
                if(item["ParentItemId"]?.ToString()!=parentSelected.ToString() &&
                    !string.Equals(item["ParentCode"]?.ToString(),parentSelected.ToString(),StringComparison.Ordinal))
                    throw new ArgumentException($"Dropdown '{key}' does not belong to the selected parent.");
            }
        }
    }
    private static void ValidateFields(List<Dictionary<string,object?>> fields,JsonElement values)
    {
        if (values.ValueKind!=JsonValueKind.Object) throw new ArgumentException("Form values must be a JSON object.");
        var permitted=fields.Select(f=>f["FieldKey"]?.ToString()).ToHashSet(StringComparer.Ordinal);
        foreach(var supplied in values.EnumerateObject())
            if(!permitted.Contains(supplied.Name))
                throw new ArgumentException($"Field '{supplied.Name}' is not in the published form.");
        foreach(var f in fields)
        {
            var name=(string)f["FieldKey"]!;
            var present=values.TryGetProperty(name,out var value) && value.ValueKind != JsonValueKind.Null;
            var valueText=present ? value.ToString() : "";
            var isFile=string.Equals(f["FieldType"]?.ToString(),"attachment",StringComparison.OrdinalIgnoreCase);
            if (Convert.ToBoolean(f["IsRequired"]) && (!present || (isFile ? value.ValueKind!=JsonValueKind.Array || value.GetArrayLength()==0 : string.IsNullOrWhiteSpace(valueText))))
                throw new ArgumentException($"Required field '{name}' is missing.");
            if (!present)continue;
            var type=(f["FieldType"]?.ToString()??"text").ToLowerInvariant();
            if(isFile)
            {
                if(value.ValueKind!=JsonValueKind.Array)throw new ArgumentException($"Attachment '{name}' must be an array of document IDs.");
                if(value.EnumerateArray().Any(item=>item.ValueKind is not (JsonValueKind.String or JsonValueKind.Number) ||
                    !long.TryParse(item.ToString(),out var id) || id<=0))
                    throw new ArgumentException($"Attachment '{name}' contains an invalid document reference.");
                continue;
            }
            switch(type)
            {
                case "number":
                    if(value.ValueKind!=JsonValueKind.Number || !value.TryGetDecimal(out _))
                        throw new ArgumentException($"Field '{name}' must be a finite number.");
                    break;
                case "date":
                    if(value.ValueKind!=JsonValueKind.String || !DateTimeOffset.TryParse(valueText,
                        CultureInfo.InvariantCulture,DateTimeStyles.AllowWhiteSpaces|DateTimeStyles.AssumeUniversal,out _))
                        throw new ArgumentException($"Field '{name}' must be a valid date.");
                    break;
                case "checkbox":
                    if(value.ValueKind is not (JsonValueKind.True or JsonValueKind.False) ||
                        Convert.ToBoolean(f["IsRequired"]) && value.ValueKind!=JsonValueKind.True)
                        throw new ArgumentException($"Field '{name}' must be checked if required.");
                    break;
                case "select":
                    if(value.ValueKind is not (JsonValueKind.String or JsonValueKind.Number))
                        throw new ArgumentException($"Field '{name}' must be a lookup item.");
                    break;
                case "email":
                    if(value.ValueKind!=JsonValueKind.String || valueText.Length>320 ||
                        !System.Net.Mail.MailAddress.TryCreate(valueText,out var address) ||
                        string.IsNullOrWhiteSpace(address.Host) || !address.Address.Equals(valueText,StringComparison.Ordinal))
                        throw new ArgumentException($"Field '{name}' must be a valid email address.");
                    break;
                default:
                    if(value.ValueKind!=JsonValueKind.String)
                        throw new ArgumentException($"Field '{name}' must be text.");
                    if(valueText.Length>10000)
                        throw new ArgumentException($"Field '{name}' exceeds the maximum text length.");
                    break;
            }
            if (string.IsNullOrEmpty(valueText) || f["RegexPattern"] is not string pattern || string.IsNullOrWhiteSpace(pattern))continue;
            try
            {
                if (!Regex.IsMatch(valueText,pattern,RegexOptions.CultureInvariant,TimeSpan.FromMilliseconds(150)))
                    throw new ArgumentException(f["RegexMessage"]?.ToString() ?? $"Field '{name}' does not match its validation rule.");
            }
            catch (RegexMatchTimeoutException) { throw new ArgumentException($"Validation of '{name}' timed out."); }
            catch (ArgumentException ex) when (ex.Message.Contains("pattern",StringComparison.OrdinalIgnoreCase))
            { throw new ArgumentException($"The configured regex for '{name}' is invalid."); }
        }
    }
}
