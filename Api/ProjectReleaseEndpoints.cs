using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;

namespace WorkflowPlatform.Api.Api;

// Maintains the existing /release routes for compatibility; the single source of truth is core.Projects.Status.
public sealed record PromoteProjectReleaseRequest(string? TargetStage, string? ExpectedStatus, string? Notes);

public static class ProjectReleaseEndpoints
{
    public static void MapProjectReleaseEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/projects/{projectId:long}/release", async (
            long projectId, HttpContext context, ActorResolver actors,
            ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            var actor = await actors.ResolveAsync(context.User, ct);
            await access.RequireAdminAsync(actor, projectId, ct);
            var result = await db.QueryAsync(@"
SELECT p.ProjectId AS projectId,p.Name AS projectName,p.Status AS stage,p.Status AS status,
       p.UpdatedAt AS updatedAt
FROM core.Projects p WHERE p.ProjectId=@projectId;
SELECT TOP (100) h.StatusChangeId AS statusChangeId, h.FromStatus AS fromStatus,
       h.ToStatus AS toStatus, h.Description AS description, h.ChangedAt AS changedAt,
       u.DisplayName AS actorName
FROM core.ProjectStatusHistory h
JOIN auth.Users u ON u.UserId=h.ChangedBy
WHERE h.ProjectId=@projectId ORDER BY h.StatusChangeId DESC;",
                new[] { SqlDatabase.G("projectId", projectId) }, ct);
            if (result.First.Count == 0) return Results.NotFound();
            return Results.Ok(new {
                release = result.First[0],
                history = result.Sets.Count > 1 ? result.Sets[1] : new List<Dictionary<string, object?>>()
            });
        });

        api.MapPost("/projects/{projectId:long}/release/promote", async (
            long projectId, PromoteProjectReleaseRequest request, HttpContext context,
            ActorResolver actors, ProjectAccess access, SqlDatabase db, CancellationToken ct) =>
        {
            var actor = await actors.ResolveAsync(context.User, ct);
            await access.RequireAdminAsync(actor, projectId, ct);
            if (!actor.PlatformAdmin) return Results.Forbid();
            var target = request.TargetStage?.Trim();
            var expected = request.ExpectedStatus?.Trim();
            if (target is not ("UAT" or "Live"))
                return Results.BadRequest(new { detail = "Choose UAT or Live." });
            if (expected is not ("Draft" or "UAT" or "Live"))
                return Results.BadRequest(new { detail = "Refresh the project before changing its status." });
            if (request.Notes?.Length > 1000)
                return Results.BadRequest(new { detail = "Description must not exceed 1000 characters." });
            var result = await db.ProcedureAsync("core.usp_ChangeProjectStatus", new[] {
                SqlDatabase.G("ActorUserId",actor.UserId),
                SqlDatabase.G("ProjectId",projectId),
                SqlDatabase.S("TargetStatus",target),
                SqlDatabase.S("ExpectedStatus",expected),
                SqlDatabase.S("Description",string.IsNullOrWhiteSpace(request.Notes) ? null : request.Notes.Trim()),
                new SqlArgument("StatusChangeId",null,System.Data.SqlDbType.BigInt,IsOutput:true)
            },ct);
            return Results.Ok(new { statusChangeId=result.Outputs.GetValueOrDefault("StatusChangeId"), status=target });
        });
    }
}
