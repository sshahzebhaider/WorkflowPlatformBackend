using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace WorkflowPlatform.Api.Services;

/// <summary>
/// Strict, data-only REST request binding. Inputs come from approved case/form mappings or an
/// authorized admin test request. No script, URL, token, or arbitrary HTTP header is evaluated.
/// </summary>
public static class RestRequestBuilder
{
    private static readonly Regex Token = new(@"\{\{\s*([A-Za-z_][A-Za-z0-9_.]*)\s*\}\}",RegexOptions.Compiled);
    private static readonly Regex Name = new(@"^[A-Za-z_][A-Za-z0-9_]{0,99}$",RegexOptions.Compiled);
    private static readonly Regex JsonPath = new(@"^[A-Za-z_][A-Za-z0-9_-]{0,99}(\.[A-Za-z_][A-Za-z0-9_-]{0,99}){0,5}$",RegexOptions.Compiled);
    private static readonly Regex FlatKey = new(@"^[A-Za-z_][A-Za-z0-9_-]{0,99}$",RegexOptions.Compiled);
    private static readonly HashSet<string> ReservedHeaders = new(StringComparer.OrdinalIgnoreCase) { "x-idempotency-key", "x-forwarded-for", "x-forwarded-host", "x-forwarded-proto", "x-original-url", "x-rewrite-url", "x-dev-user", "x-http-method-override" };
    private static readonly Regex Header = new(@"^(x-[a-z0-9-]+|accept)$",RegexOptions.IgnoreCase|RegexOptions.Compiled);
    public sealed record Result(string Path,string? BodyJson,Dictionary<string,string> Headers);

    public static Result Build(string path,string? template,string? paramsJson,string? headersJson,
        IReadOnlyDictionary<string,JsonElement> input,string method)
    {
        if (!path.StartsWith('/') || path.StartsWith("//") || path.Contains("..") || path.Contains('#'))
            throw new ArgumentException("Operation must use a safe relative API path.");
        var values=input.ToDictionary(x=>x.Key,x=>x.Value,StringComparer.Ordinal);
        var query=new List<KeyValuePair<string,string>>();
        var headers=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        var body=string.IsNullOrWhiteSpace(template)?null:JsonNode.Parse(template);
        if(body is JsonObject emptyObject && emptyObject.Count==0)body=null;
        if (body is not null && method=="GET" && body is JsonObject obj && obj.Count>0)
            throw new ArgumentException("GET operations cannot send JSON bodies.");
        if (!string.IsNullOrWhiteSpace(headersJson))
        {
            using var doc=JsonDocument.Parse(headersJson);
            if (doc.RootElement.ValueKind!=JsonValueKind.Object) throw new ArgumentException("Headers must be a JSON object.");
            foreach(var h in doc.RootElement.EnumerateObject())
            {
                if(!Header.IsMatch(h.Name) || ReservedHeaders.Contains(h.Name) || h.Value.ValueKind!=JsonValueKind.String)
                    throw new ArgumentException("Only fixed X-* and Accept string headers are supported.");
                headers[h.Name]=h.Value.GetString()??"";
            }
        }
        if(!string.IsNullOrWhiteSpace(paramsJson))
        {
            using var definitions=JsonDocument.Parse(paramsJson);
            if(definitions.RootElement.ValueKind!=JsonValueKind.Array || definitions.RootElement.GetArrayLength()>100)
                throw new ArgumentException("Request input definitions must be an array of at most 100 items.");
            var usedNames=new HashSet<string>(StringComparer.Ordinal);
            var usedTargets=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var bodyValues=new List<(string Key,JsonElement Value)>();
            foreach(var row in definitions.RootElement.EnumerateArray())
            {
                if(row.ValueKind!=JsonValueKind.Object)throw new ArgumentException("Invalid request input definition.");
                var name=Read(row,"name");var location=Read(row,"location").ToLowerInvariant();
                var key=Read(row,"key");var type=Read(row,"type","string").ToLowerInvariant();
                var required=!row.TryGetProperty("required",out var rq) || rq.ValueKind!=JsonValueKind.False;
                if(!Name.IsMatch(name) || !usedNames.Add(name))
                    throw new ArgumentException($"Invalid or duplicate request input '{name}'.");
                if(location is not ("path" or "query" or "body" or "header") ||
                   type is not ("string" or "number" or "boolean" or "object"))
                    throw new ArgumentException($"Invalid request input destination or type for '{name}'.");
                if(location=="header" && (!Header.IsMatch(key) || ReservedHeaders.Contains(key)))throw new ArgumentException("Dynamic header is not allowed.");
                if(location=="body" && !JsonPath.IsMatch(key) || (location=="query" || location=="path") && !FlatKey.IsMatch(key))
                    throw new ArgumentException($"Invalid request key for '{name}'.");
                if(location=="path" && !Token.Matches(path).Cast<Match>().Any(m=>m.Groups[1].Value==name))
                    throw new ArgumentException($"Path input '{name}' must be referenced by its placeholder.");
                if(location=="body" && (method is "GET" or "DELETE"))
                    throw new ArgumentException($"{method} operations cannot have mapped body parameters.");
                if(location!="path" && !usedTargets.Add(location+":"+key))
                    throw new ArgumentException($"Duplicate request target '{location}:{key}'.");
                if(!values.TryGetValue(name,out var raw) || Empty(raw))
                {
                    if(row.TryGetProperty("defaultValue",out var fallback) && !Empty(fallback))raw=fallback;
                    else if(required)throw new ArgumentException($"Missing required integration input '{name}'.");
                    else continue;
                }
                var converted=Coerce(raw,type,name);
                values[name]=converted;
                if(location=="query")query.Add(new(key,AsString(converted)));
                else if(location=="header")headers[key]=AsString(converted);
                else if(location=="body")bodyValues.Add((key,converted));
            }
            // Resolve the fixed template BEFORE adding user-supplied mapped body values.
            // External user values containing "{{...}}" must never become new template expressions.
            body=body is null?null:ExpandNode(body,values);
            foreach(var (key,value) in bodyValues)
            {
                body ??=new JsonObject();
                if(body is not JsonObject root)throw new ArgumentException("JSON body must be an object for body parameter mapping.");
                SetBody(root,key,JsonNode.Parse(value.GetRawText()));
            }
        }
        else if(body is not null)body=ExpandNode(body,values);
        var serialized=body?.ToJsonString();
        var requestPath=Expand(path,values,true);
        if(query.Count>0)requestPath+=(requestPath.Contains('?')?"&":"?")+string.Join("&",query.Select(p=>Uri.EscapeDataString(p.Key)+"="+Uri.EscapeDataString(p.Value)));
        if(requestPath.Length>2000)throw new ArgumentException("Request path exceeds maximum length.");
        return new Result(requestPath,serialized,headers);
    }
    private static string Read(JsonElement row,string key,string fallback="") =>
        row.TryGetProperty(key,out var val) && val.ValueKind==JsonValueKind.String ? val.GetString()??fallback : fallback;
    private static bool Empty(JsonElement value) => value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined ||
        value.ValueKind==JsonValueKind.String && string.IsNullOrWhiteSpace(value.GetString());
    private static string AsString(JsonElement value)=> value.ValueKind==JsonValueKind.String?value.GetString()??"":value.ToString();
    private static JsonElement Coerce(JsonElement input,string type,string name)
    {
        if(type=="number")
        {
            if(!decimal.TryParse(AsString(input),NumberStyles.Number,CultureInfo.InvariantCulture,out var d))
                throw new ArgumentException($"Integration input '{name}' must be numeric.");
            return JsonSerializer.SerializeToElement(d);
        }
        if(type=="boolean")
        {
            if(!bool.TryParse(AsString(input),out var b))
                throw new ArgumentException($"Integration input '{name}' must be true or false.");
            return JsonSerializer.SerializeToElement(b);
        }
        if(type=="object")
        {
            if(input.ValueKind is JsonValueKind.Object or JsonValueKind.Array)return input.Clone();
            try { using var obj=JsonDocument.Parse(AsString(input));
                if(obj.RootElement.ValueKind is JsonValueKind.Object or JsonValueKind.Array)return obj.RootElement.Clone(); }
            catch(JsonException) { }
            throw new ArgumentException($"Integration input '{name}' must be JSON object/array.");
        }
        if(input.ValueKind is JsonValueKind.Array or JsonValueKind.Object)
            throw new ArgumentException($"Integration input '{name}' must be a scalar.");
        var value=AsString(input);
        if(value.Length>2048)throw new ArgumentException($"Integration input '{name}' exceeds maximum length.");
        return JsonSerializer.SerializeToElement(value);
    }
    private static void SetBody(JsonObject body,string path,JsonNode? value)
    {
        var keys=path.Split('.');var node=body;
        for(var i=0;i<keys.Length-1;i++)
        {
            if(node[keys[i]] is null)node[keys[i]]=new JsonObject();
            node=node[keys[i]] as JsonObject ?? throw new ArgumentException($"Body key '{path}' conflicts with a non-object property.");
        }
        node[keys[^1]]=value;
    }
    private static string Expand(string text,IReadOnlyDictionary<string,JsonElement> values,bool escape=false)=>Token.Replace(text,m=>
    {
        var name=m.Groups[1].Value;
        if(!values.TryGetValue(name,out var value)||Empty(value))throw new ArgumentException($"Missing required integration input '{name}'.");
        var output=AsString(value);
        return escape?Uri.EscapeDataString(output):output;
    });
    private static JsonNode ExpandNode(JsonNode node,IReadOnlyDictionary<string,JsonElement> values)
    {
        if(node is JsonObject obj)
        {
            var result=new JsonObject();foreach(var child in obj)result[child.Key]=child.Value is null?null:ExpandNode(child.Value,values);return result;
        }
        if(node is JsonArray array)
        {
            var result=new JsonArray();foreach(var child in array)result.Add(child is null?null:ExpandNode(child,values));return result;
        }
        var value=node.GetValueKind()==JsonValueKind.String?node.GetValue<string>():null;
        if(value is null)return node.DeepClone();
        var matched=Token.Match(value);
        if(matched.Success && matched.Length==value.Length)
        {
            var name=matched.Groups[1].Value;
            if(!values.TryGetValue(name,out var actual)||Empty(actual))throw new ArgumentException($"Missing required integration input '{name}'.");
            return JsonNode.Parse(actual.GetRawText())!;
        }
        return JsonValue.Create(Expand(value,values))!;
    }
}
