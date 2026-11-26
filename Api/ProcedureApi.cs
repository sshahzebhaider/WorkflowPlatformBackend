using System.Data;
using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;

namespace WorkflowPlatform.Api.Api;

public sealed record Field(string Name, SqlDbType Type, bool Required = false, bool Output = false);

public static class ProcedureApi
{
    public static Field G(string name, bool required = true) => new(name, SqlDbType.BigInt, required);
    public static Field S(string name, bool required = false) => new(name, SqlDbType.NVarChar, required);
    public static Field J(string name, bool required = true) => new(name, SqlDbType.NVarChar, required);
    public static Field I(string name, bool required = false) => new(name, SqlDbType.Int, required);
    public static Field B(string name, bool required = false) => new(name, SqlDbType.Bit, required);
    public static Field D(string name, bool required = true) => new(name, SqlDbType.Date, required);
    public static Field O(string name) => new(name, SqlDbType.BigInt, Output: true);

    public static void MapProc(this RouteGroupBuilder group, string path, string proc,
        string? guard, params Field[] fields)
    {
        group.MapPost(path, async (HttpContext http, SqlDatabase db, ActorResolver resolver,
            ProjectAccess access, CancellationToken ct) =>
        {
            var actor = await resolver.ResolveAsync(http.User, ct);
            long? projectId = null;
            if (http.Request.RouteValues.TryGetValue("projectId", out var routeProject) && routeProject is not null)
                projectId = long.Parse(routeProject.ToString()!);
            // An explicit null scope means platform-wide authorization; project resources use path projectId.
            var body = http.Request.HasJsonContentType() ? await http.Request.ReadFromJsonAsync<JsonElement>(cancellationToken: ct) : default;
            if (body.ValueKind is not (JsonValueKind.Object or JsonValueKind.Undefined))
                throw new ArgumentException("Expected a JSON object body.");
            if (projectId is null && body.ValueKind == JsonValueKind.Object && TryProperty(body,"ProjectId",out var bodyProject)
                && bodyProject.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined) && long.TryParse(bodyProject.ToString(),out var bodyId))
                projectId = bodyId;
            if (guard is not null)
            {
                if (guard == "admin") await access.RequireAdminAsync(actor, projectId, ct);
                else if (guard == "platformAdmin") await access.RequireAdminAsync(actor, null, ct);
                else await access.RequireAsync(actor, projectId, guard, ct);
            }
            // Directory user upsert has no ActorUserId parameter in the finalized SQL contract.
            var args = new List<SqlArgument>();
            if (proc != "auth.usp_UpsertDirectoryUser") args.Add(SqlDatabase.G("ActorUserId", actor.UserId));
            foreach (var f in fields)
            {
                if (f.Output)
                {
                    object? supplied = null;
                    if (body.ValueKind == JsonValueKind.Object && TryProperty(body,f.Name,out var suppliedElement)
                        && suppliedElement.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined)
                        && long.TryParse(suppliedElement.ToString(),out var suppliedId)) supplied = suppliedId;
                    args.Add(new SqlArgument(f.Name,supplied,f.Type,IsOutput:true)); continue;
                }
                if (f.Name == "ProjectId" && projectId is not null) { args.Add(SqlDatabase.G("ProjectId", projectId)); continue; }
                JsonElement item = default;
                var present = body.ValueKind == JsonValueKind.Object && TryProperty(body, f.Name, out item);
                if (!present && http.Request.RouteValues.TryGetValue(f.Name, out var routeValue) && routeValue is not null)
                {
                    // Route values are converted through the same value validation path.
                    item = JsonSerializer.SerializeToElement(routeValue.ToString()); present = true;
                }
                if (!present)
                {
                    if (f.Required) throw new ArgumentException($"{Camel(f.Name)} is required.");
                    // Some procedures require @Code even though NULL means auto-generate from the name.
                    if (f.Name == "Code") args.Add(new SqlArgument("Code", null, f.Type));
                    continue;
                }
                var value = ConvertField(f, item);
                if (value is null && f.Required) throw new ArgumentException($"{Camel(f.Name)} is required.");
                args.Add(new SqlArgument(f.Name, value, f.Type, f.Type == SqlDbType.NVarChar ? -1 : null));
            }
            var result = await db.ProcedureAsync(proc, args, ct);
            return Results.Ok(new { data = result.First, sets = result.Sets, outputs = result.Outputs });
        }).WithName("proc_" + proc.Replace('.', '_'));
    }
    private static bool TryProperty(JsonElement body, string name, out JsonElement value)
    {
        foreach (var property in body.EnumerateObject())
            if (property.Name.Equals(name, StringComparison.OrdinalIgnoreCase) ||
                property.Name.Equals(Camel(name), StringComparison.OrdinalIgnoreCase))
            { value = property.Value; return true; }
        value = default; return false;
    }
    private static string Camel(string value) => char.ToLowerInvariant(value[0]) + value[1..];
    private static object? ConvertField(Field field, JsonElement value)
    {
        if (value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return null;
        return field.Type switch
        {
            SqlDbType.BigInt => long.TryParse(value.ToString(), out var id) && id > 0 ? id : throw new ArgumentException($"{field.Name} must be a valid positive database-generated numeric ID."),
            SqlDbType.Int => value.TryGetInt32(out int integer) ? integer : throw new ArgumentException($"Invalid integer for {field.Name}."),
            SqlDbType.Bit => value.ValueKind == JsonValueKind.True || (value.ValueKind == JsonValueKind.False ? false : bool.Parse(value.ToString())),
            SqlDbType.Date => DateTime.Parse(value.ToString(), CultureInfo.InvariantCulture).Date,
            SqlDbType.DateTime2 => DateTime.Parse(value.ToString(), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind),
            _ when value.ValueKind is JsonValueKind.Object or JsonValueKind.Array => value.GetRawText(),
            _ => value.ToString()
        };
    }
}
