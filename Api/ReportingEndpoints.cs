using System.Data;
using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;

namespace WorkflowPlatform.Api.Api;

/// <summary>
/// Safe project-scoped log/report explorer. Columns and SQL source clauses are defined in
/// source code, never supplied by the client. Audit and case-event detail requires admin rights.
/// </summary>
public static class ReportingEndpoints
{
    private sealed record Field(string Key,string Label,string Expression);
    private sealed record Source(string Key,string Label,string FromAndScope,string DateExpression,
        string OrderExpression,string SearchExpression,bool AdminOnly,Field[] Columns);
    private static readonly Source[] Sources =
    [
        new("cases","Cases","FROM work.Cases c WHERE c.ProjectId=@project","c.CreatedAt","c.CaseId",
            "(c.ReferenceNo LIKE N'%'+@search+N'%' OR c.Title LIKE N'%'+@search+N'%')",false,
            [new("caseId","Case ID","c.CaseId"),new("reference","Reference","c.ReferenceNo"),
             new("title","Title","c.Title"),new("status","Status","c.Status"),new("priority","Priority","c.Priority"),
             new("createdAt","Created","c.CreatedAt"),new("dueAt","TAT due","c.DueAt"),
             new("closedAt","Closed","c.ClosedAt"),new("createdBy","Created by user ID","c.CreatedBy")]),
        new("caseEvents","Case logs / events",
            "FROM work.CaseEvents e JOIN work.Cases c ON c.CaseId=e.CaseId WHERE c.ProjectId=@project",
            "e.OccurredAt","e.EventId","(c.ReferenceNo LIKE N'%'+@search+N'%' OR e.Message LIKE N'%'+@search+N'%')",true,
            [new("eventId","Event ID","e.EventId"),new("reference","Case reference","c.ReferenceNo"),
             new("eventType","Event","e.EventType"),new("message","Message","e.Message"),
             new("actorUserId","Actor user ID","e.ActorUserId"),new("occurredAt","Occurred","e.OccurredAt"),
             new("detailsJson","Details JSON","e.DetailsJson")]),
        new("auditEvents","Project audit logs","FROM audit.Events a WHERE a.ProjectId=@project",
            "a.OccurredAt","a.AuditId","(a.EntityType LIKE N'%'+@search+N'%' OR a.ActionCode LIKE N'%'+@search+N'%')",true,
            [new("auditId","Audit ID","a.AuditId"),new("entityType","Entity","a.EntityType"),
             new("entityId","Entity ID","a.EntityId"),new("actionCode","Action","a.ActionCode"),
             new("actorUserId","Actor user ID","a.ActorUserId"),new("occurredAt","Occurred","a.OccurredAt"),
             new("detailsJson","Details JSON","a.DetailsJson")]),
        new("tasks","Tasks",
            "FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId JOIN work.Cases c ON c.CaseId=i.CaseId WHERE c.ProjectId=@project",
            "t.CreatedAt","t.TaskId","(c.ReferenceNo LIKE N'%'+@search+N'%' OR t.ActionCode LIKE N'%'+@search+N'%')",false,
            [new("taskId","Task ID","t.TaskId"),new("reference","Case reference","c.ReferenceNo"),
             new("status","Status","t.Status"),new("routingStage","Routing stage","t.RoutingStage"),
             new("assignedTo","Assigned user ID","t.AssignedTo"),new("teamId","Team ID","t.TeamId"),
             new("createdAt","Created","t.CreatedAt"),new("dueAt","Task due","t.DueAt"),
             new("completedAt","Completed","t.CompletedAt"),new("actionCode","Action","t.ActionCode")]),
        new("tatBreaches","Case TAT breaches",
            "FROM work.CaseTatBreaches b JOIN work.Cases c ON c.CaseId=b.CaseId WHERE b.ProjectId=@project",
            "b.BreachedAtUtc","b.CaseId","(c.ReferenceNo LIKE N'%'+@search+N'%' OR c.Title LIKE N'%'+@search+N'%')",true,
            [new("caseId","Case ID","b.CaseId"),new("reference","Case reference","c.ReferenceNo"),
             new("dueAtUtc","TAT due","b.DueAtUtc"),new("breachedAtUtc","Breached","b.BreachedAtUtc")]),
        new("caseTypes","Case types","FROM core.CaseTypes ct WHERE ct.ProjectId=@project",
            "ct.UpdatedAt","ct.CaseTypeId","(ct.Name LIKE N'%'+@search+N'%' OR ct.Code LIKE N'%'+@search+N'%')",false,
            [new("caseTypeId","Case Type ID","ct.CaseTypeId"),new("code","Code","ct.Code"),
             new("name","Name","ct.Name"),new("isActive","Active","ct.IsActive"),
             new("liveVersionId","Published version ID","ct.LiveVersionId"),new("updatedAt","Updated","ct.UpdatedAt")]),
        new("teams","Teams","FROM teams.Teams tm WHERE tm.ProjectId=@project",
            "tm.CreatedAt","tm.TeamId","(tm.Name LIKE N'%'+@search+N'%' OR tm.Code LIKE N'%'+@search+N'%')",false,
            [new("teamId","Team ID","tm.TeamId"),new("code","Code","tm.Code"),
             new("name","Name","tm.Name"),new("isActive","Active","tm.IsActive"),
             new("createdAt","Created","tm.CreatedAt")]),
        new("projectStatus","Project status history",
            "FROM core.ProjectStatusHistory h WHERE h.ProjectId=@project",
            "h.ChangedAt","h.StatusChangeId","(h.FromStatus LIKE N'%'+@search+N'%' OR h.ToStatus LIKE N'%'+@search+N'%')",true,
            [new("statusChangeId","History ID","h.StatusChangeId"),new("fromStatus","From","h.FromStatus"),
             new("toStatus","To","h.ToStatus"),new("description","Description","h.Description"),
             new("changedBy","Changed by user ID","h.ChangedBy"),new("changedAt","Changed","h.ChangedAt")]),
        new("project","Project information","FROM core.Projects p WHERE p.ProjectId=@project",
            "p.CreatedAt","p.ProjectId","(p.Name LIKE N'%'+@search+N'%' OR p.Code LIKE N'%'+@search+N'%')",false,
            [new("projectId","Project ID","p.ProjectId"),new("code","Code","p.Code"),
             new("name","Name","p.Name"),new("status","Status","p.Status"),
             new("calendarId","Calendar ID","p.CalendarId"),
             new("defaultSlaMinutes","Default SLA minutes","p.DefaultSlaMinutes"),
             new("createdAt","Created","p.CreatedAt"),new("updatedAt","Updated","p.UpdatedAt")])
    ];

    public static void MapReportingEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/projects/{projectId:long}/reports/catalog", async(long projectId,HttpContext ctx,
            ActorResolver actors,ProjectAccess access,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await access.RequireAsync(actor,projectId,"reports.view",ct);
            return Results.Ok(Sources.Select(s=>new {
                key=s.Key,label=s.Label,adminOnly=s.AdminOnly,
                columns=s.Columns.Select(c=>new {key=c.Key,label=c.Label})
            }));
        });
        api.MapGet("/projects/{projectId:long}/reports/query", async(long projectId,string source,
            string? columns,DateTime? fromUtc,DateTime? toUtc,string? search,int? page,int? pageSize,
            HttpContext ctx,ActorResolver actors,ProjectAccess access,SqlDatabase db,CancellationToken ct) =>
        {
            var actor=await actors.ResolveAsync(ctx.User,ct);
            await access.RequireAsync(actor,projectId,"reports.view",ct);
            var definition=Sources.FirstOrDefault(x=>string.Equals(x.Key,source,StringComparison.Ordinal));
            if(definition is null)return Results.BadRequest(new {detail="Unknown report source."});
            // Detailed logs and project-wide case data are more sensitive than summary counts.
            // Team members retain summary access; only project admins can query row-level data.
            await access.RequireAdminAsync(actor,projectId,ct);
            if(fromUtc.HasValue&&toUtc.HasValue&&fromUtc.Value>toUtc.Value)
                return Results.BadRequest(new {detail="Invalid date range."});
            var keys=string.IsNullOrWhiteSpace(columns)
                ? definition.Columns.Take(7).Select(x=>x.Key).ToArray()
                : columns.Split(',',StringSplitOptions.TrimEntries|StringSplitOptions.RemoveEmptyEntries);
            if(keys.Length==0||keys.Length>25||keys.Distinct(StringComparer.Ordinal).Count()!=keys.Length
               ||keys.Any(k=>!definition.Columns.Any(f=>f.Key==k)))
                return Results.BadRequest(new {detail="Choose valid, distinct report columns."});
            // Only expressions from our compiled, static allowlist enter the SQL statement.
            var fieldSql=string.Join(",",keys.Select(k=>{
                var f=definition.Columns.First(c=>c.Key==k);
                return f.Expression+" AS ["+f.Key+"]";
            }));
            var filter=" AND (@fromUtc IS NULL OR "+definition.DateExpression+">=@fromUtc)"+
                " AND (@toUtc IS NULL OR "+definition.DateExpression+"<=@toUtc)"+
                " AND (@search IS NULL OR "+definition.SearchExpression+")";
            var sql="SELECT "+fieldSql+" "+definition.FromAndScope+filter+
                " ORDER BY "+definition.OrderExpression+" DESC OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY;"+
                " SELECT COUNT_BIG(*) AS Total "+definition.FromAndScope+filter+";";
            var currentPage=Math.Clamp(page??1,1,100000);
            var take=Math.Clamp(pageSize??50,1,200);
            var result=await db.QueryAsync(sql, new SqlArgument[] {
                SqlDatabase.G("project",projectId),
                new("fromUtc",fromUtc,SqlDbType.DateTime2),new("toUtc",toUtc,SqlDbType.DateTime2),
                SqlDatabase.S("search",string.IsNullOrWhiteSpace(search)?null:search.Trim()[..Math.Min(200,search.Trim().Length)]),
                new("skip",(currentPage-1)*take,SqlDbType.Int),new("take",take,SqlDbType.Int)
            },ct);
            var total=result.Sets.Count>1 && result.Sets[1].Count>0
                ? Convert.ToInt64(result.Sets[1][0]["Total"]):0L;
            return Results.Ok(new {rows=result.First,total,page=currentPage,pageSize=take,columns=keys});
        });
    }
}
