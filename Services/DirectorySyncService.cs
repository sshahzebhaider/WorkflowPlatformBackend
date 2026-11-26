using System.Net.Http.Headers;
using System.Text.Json;
using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;

namespace WorkflowPlatform.Api.Services;

/// <summary>Explicit Microsoft Entra ID directory import. Requires Graph User.Read.All application
/// permission with admin consent. Missing accounts are never inferred to have resigned: that
/// requires the authenticated manual offboarding action or an authoritative HR signal.</summary>
public sealed class DirectorySyncService(IHttpClientFactory clients,IConfiguration configuration,SqlDatabase db)
{
    public async Task<object> SyncAsync(Actor actor,CancellationToken ct)
    {
        var tenant=configuration["DirectorySync:TenantId"];
        var clientId=configuration["DirectorySync:ClientId"];
        var clientSecret=configuration["DirectorySync:ClientSecret"];
        if(!Guid.TryParse(tenant,out _) || !Guid.TryParse(clientId,out _) || string.IsNullOrWhiteSpace(clientSecret))
            throw new InvalidOperationException("Entra directory sync is not configured. Set DirectorySync tenant/client credentials in secret storage.");
        var http=clients.CreateClient(); http.Timeout=TimeSpan.FromSeconds(30);
        using var tokenResponse=await http.PostAsync($"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token",
            new FormUrlEncodedContent(new Dictionary<string,string>{
                ["grant_type"]="client_credentials",["client_id"]=clientId!,
                ["client_secret"]=clientSecret!,["scope"]="https://graph.microsoft.com/.default"}),ct);
        if(!tokenResponse.IsSuccessStatusCode)throw new InvalidOperationException("Entra token request failed. Verify app registration permissions and credentials.");
        using var tokenJson=JsonDocument.Parse(await tokenResponse.Content.ReadAsStringAsync(ct));
        var token=tokenJson.RootElement.GetProperty("access_token").GetString()
            ?? throw new InvalidOperationException("The identity provider returned no token.");
        var next="https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,mail,mobilePhone,accountEnabled&$top=100";
        var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);int count=0,disabled=0;
        while(!string.IsNullOrWhiteSpace(next))
        {
            if(!Uri.TryCreate(next,UriKind.Absolute,out var pageUri)
              || pageUri.Scheme!="https" || pageUri.Host!="graph.microsoft.com" || pageUri.Port!=443)
                throw new InvalidOperationException("Invalid Microsoft Graph pagination URL.");
            using var request=new HttpRequestMessage(HttpMethod.Get,pageUri);
            request.Headers.Authorization=new AuthenticationHeaderValue("Bearer",token);
            using var response=await http.SendAsync(request,ct);
            if(!response.IsSuccessStatusCode)throw new InvalidOperationException("Microsoft Graph directory read failed.");
            using var doc=JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
            foreach(var u in doc.RootElement.GetProperty("value").EnumerateArray())
            {
                var oid=u.GetProperty("id").GetString();
                var username=u.TryGetProperty("userPrincipalName",out var p)?p.GetString():null;
                var name=u.TryGetProperty("displayName",out var d)?d.GetString():null;
                if(string.IsNullOrWhiteSpace(oid)||!Guid.TryParse(oid,out _)||string.IsNullOrWhiteSpace(username)||string.IsNullOrWhiteSpace(name))continue;
                if(!seen.Add(oid))continue;
                // Never reactivate an account explicitly marked resigned by an administrator.
                var existing=await db.ScalarAsync("SELECT COUNT(*) FROM auth.Users WHERE ExternalDirectoryId=@oid AND DirectoryStatus='Resigned'",
                    new[]{SqlDatabase.S("oid",oid)},ct);
                if(Convert.ToInt32(existing)>0)continue;
                var active=u.TryGetProperty("accountEnabled",out var enabled)&&enabled.ValueKind==JsonValueKind.True;
                var row=await db.ProcedureAsync("auth.usp_UpsertDirectoryUser",new[]{
                    SqlDatabase.S("UserName",username),SqlDatabase.S("DisplayName",name),
                    SqlDatabase.S("Email",u.TryGetProperty("mail",out var mail)&&mail.ValueKind==JsonValueKind.String?mail.GetString():null),
                    SqlDatabase.S("Mobile",u.TryGetProperty("mobilePhone",out var mobile)&&mobile.ValueKind==JsonValueKind.String?mobile.GetString():null),
                    SqlDatabase.S("ExternalDirectoryId",oid),SqlDatabase.S("DirectoryStatus",active?"Active":"Disabled"),
                    new SqlArgument("UserId",null,System.Data.SqlDbType.BigInt,IsOutput:true)},ct);
                if(!active)
                {
                    disabled++;
                    await db.ProcedureAsync("auth.usp_SetDirectoryStatus",new[]{
                        SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.G("UserId",Convert.ToInt64(row.Outputs["UserId"]!)),
                        SqlDatabase.S("DirectoryStatus","Disabled")},ct);
                }
                count++;
            }
            next=doc.RootElement.TryGetProperty("@odata.nextLink",out var link)?link.GetString():null;
            if(seen.Count>100000)throw new InvalidOperationException("Directory sync exceeded safe user limit.");
        }
        await db.ProcedureAsync("audit.usp_Write",new[]{
            SqlDatabase.G("ActorUserId",actor.UserId),SqlDatabase.S("EntityType","DirectorySync"),
            SqlDatabase.S("ActionCode","EntraSyncCompleted"),SqlDatabase.S("DetailsJson",JsonSerializer.Serialize(new { imported=count,disabled }))},ct);
        return new { imported=count,disabled };
    }
}
