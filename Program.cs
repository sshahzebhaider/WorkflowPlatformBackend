using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Data.SqlClient;
using WorkflowPlatform.Api.Api;
using WorkflowPlatform.Api.Data;
using WorkflowPlatform.Api.Security;
using WorkflowPlatform.Api.Services;

var builder = WebApplication.CreateBuilder(args);
if (!builder.Environment.IsDevelopment() &&
    (string.IsNullOrWhiteSpace(builder.Configuration["Authentication:Authority"]) ||
     string.IsNullOrWhiteSpace(builder.Configuration["Authentication:Audience"])))
    throw new InvalidOperationException("Configure a trusted JWT authority and audience before running in Production.");
if (!builder.Environment.IsDevelopment() &&
    !string.Equals(builder.Configuration["Files:ScanMode"],"ClamAV",StringComparison.OrdinalIgnoreCase))
    throw new InvalidOperationException("Production requires Files:ScanMode=ClamAV with a working ClamAV scanner.");
if (string.Equals(builder.Configuration["Notifications:DeliveryMode"],"Live",StringComparison.OrdinalIgnoreCase)
    && (string.IsNullOrWhiteSpace(builder.Configuration["Notifications:SendGrid:ApiKey"])
    || string.IsNullOrWhiteSpace(builder.Configuration["Notifications:Twilio:AuthToken"])))
    throw new InvalidOperationException("Live notification delivery requires SendGrid and Twilio credentials. Store secrets outside source control.");
builder.Services.Configure<Microsoft.AspNetCore.Http.Features.FormOptions>(options => {
    options.MultipartBodyLengthLimit=22L*1024*1024;
    options.ValueCountLimit=256;
});
builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize=24L*1024*1024);
builder.Services.AddSingleton<SqlDatabase>();
builder.Services.AddScoped<ActorResolver>();
builder.Services.AddScoped<ProjectAccess>();
builder.Services.AddHttpClient();
builder.Services.AddScoped<OperationTester>();
builder.Services.AddScoped<LodgementIntegration>();
builder.Services.AddScoped<FormRules>();
builder.Services.AddScoped<DirectorySyncService>();
builder.Services.AddScoped<PrecaseAttachmentScanner>();
builder.Services.AddHostedService<NotificationPreviewWorker>();
builder.Services.AddHostedService<NotificationDeliveryWorker>();
builder.Services.AddHostedService<TaskSlaWorker>();
builder.Services.AddHostedService<WorkflowExecutionWorker>();
builder.Services.AddHostedService<AttachmentScanWorker>();
builder.Services.AddHostedService<StagedAttachmentCleanupWorker>();
builder.Services.AddAuthentication("PlatformAuth")
    .AddPolicyScheme("PlatformAuth", "Validated JWT or development-only local identity", options =>
    {
        options.ForwardDefaultSelector = context =>
            context.Request.Headers.ContainsKey("X-Dev-User")
            && context.RequestServices.GetRequiredService<IWebHostEnvironment>().IsDevelopment()
            && context.RequestServices.GetRequiredService<IConfiguration>().GetValue<bool>("Authentication:EnableDevHeaderAuth")
            ? "DevHeader" : JwtBearerDefaults.AuthenticationScheme;
    })
    .AddScheme<AuthenticationSchemeOptions, DevHeaderHandler>("DevHeader", _ => { })
    .AddJwtBearer(options =>
    {
        options.Authority = builder.Configuration["Authentication:Authority"];
        options.Audience = builder.Configuration["Authentication:Audience"];
        options.RequireHttpsMetadata = !builder.Environment.IsDevelopment();
        options.MapInboundClaims = false;
        options.TokenValidationParameters.ValidateIssuer = true;
        options.TokenValidationParameters.ValidateAudience = true;
        options.TokenValidationParameters.ValidateLifetime = true;
    });
builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(options => {
    options.RejectionStatusCode=429;
    options.GlobalLimiter=PartitionedRateLimiter.Create<HttpContext,string>(ctx =>
        !ctx.Request.Path.StartsWithSegments("/api") ? RateLimitPartition.GetNoLimiter("health") :
        RateLimitPartition.GetFixedWindowLimiter(ctx.User.FindFirst("sub")?.Value ?? ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new FixedWindowRateLimiterOptions {
            PermitLimit=Math.Clamp(builder.Configuration.GetValue<int?>("Security:RequestsPerMinute") ?? 600,60,6000), Window=TimeSpan.FromMinutes(1), QueueLimit=0
        }));
});
var origins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? Array.Empty<string>();
builder.Services.AddCors(options => options.AddPolicy("frontend", p => p.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();
app.UseExceptionHandler(handler => handler.Run(async ctx =>
{
    var exception = ctx.Features.Get<Microsoft.AspNetCore.Diagnostics.IExceptionHandlerFeature>()?.Error;
    if (exception is null) return;
    var (status, title, detail) = exception switch
    {
        AccessDeniedException => (403, "Forbidden", "Insufficient privileges."),
        UnauthorizedAccessException => (401, "Unauthorized", "Identity is not recognized or is inactive."),
        ArgumentException arg => (400, "Validation error", arg.Message),
        SqlException sql when sql.Number is 50224 => (403, "Forbidden", "Insufficient privileges."),
        SqlException sql when sql.Number is 50223 => (404, "Not found", "Case not found."),
        SqlException sql when sql.Number is 2601 or 2627 => (409, "Already exists", "A record with the same unique key already exists."),
        SqlException sql when sql.Number is 51001 => (403, "Forbidden", "Insufficient privileges."),
        SqlException sql when sql.Number is 51002 or 51005 => (400, "Business rule violation", sql.Message),
        SqlException sql when sql.Number is >= 50000 and <= 50999 => (400, "Business rule violation", sql.Message),
        SqlException sql when sql.Number is 547 => (409, "Related records exist", "The operation violates a database relationship."),
        _ => (500, "Server error", "The operation could not be completed. Consult server logs.")
    };
    if (status >= 500) app.Logger.LogError(exception, "Request failed: {Path}", ctx.Request.Path);
    else app.Logger.LogWarning("Request rejected: {Path}, status={Status}, errorType={ErrorType}",ctx.Request.Path,status,exception.GetType().Name);
    ctx.Response.StatusCode = status;
    await ctx.Response.WriteAsJsonAsync(new { type = "about:blank", title, status, detail,
        traceId = ctx.TraceIdentifier });
}));
if (!app.Environment.IsDevelopment()) app.UseHsts();
app.Use(async (ctx,next) => {
    ctx.Response.Headers["X-Content-Type-Options"]="nosniff";
    if(ctx.Request.Path.StartsWithSegments("/api")) ctx.Response.Headers["Cache-Control"]="no-store";
    await next();
});
app.UseCors("frontend");
app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();

app.MapGet("/health/live", () => Results.Ok(new { status = "alive" }));
app.MapGet("/health/ready", async (SqlDatabase db, CancellationToken ct) =>
{
    // Fail fast if the server is accidentally pointed at the legacy UUID-based database.
    // A live schema mismatch must never be silently masked as an empty workspace.
    var numericSchema = await db.ScalarAsync(@"
SELECT CASE WHEN EXISTS (
  SELECT 1 FROM sys.columns c
  WHERE c.object_id=OBJECT_ID(N'auth.Users',N'U')
    AND c.name=N'UserId' AND c.system_type_id=TYPE_ID(N'bigint')
) AND OBJECT_ID(N'auth.Seq_Users',N'SO') IS NOT NULL
 AND COL_LENGTH(N'integration.Executions',N'ClaimVersion') IS NOT NULL
 AND OBJECT_ID(N'files.usp_CreateStagedDocument',N'P') IS NOT NULL
 AND OBJECT_ID(N'integration.usp_RetryFailedRead',N'P') IS NOT NULL
THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END", [], ct);
    if(numericSchema is null || !Convert.ToBoolean(numericSchema))
        return Results.Problem(statusCode:503, title:"Wrong database schema",
          detail:"Configure ConnectionStrings:Default for WorkflowPlatformV2 and run the numeric schema installer.");
    await db.ProcedureAsync("core.usp_DatabaseHealth", [], ct);
    return Results.Ok(new { status = "ready", schema = "Int64Sequence" });
}); // For a public deployment, restrict readiness output to monitoring infrastructure.

var api = app.MapGroup("/api").RequireAuthorization();
api.MapIdentityEndpoints();
api.MapPlatformEndpoints();
api.MapProjectReleaseEndpoints();
api.MapConfigurationEndpoints();
api.MapWorkEndpoints();
api.MapIntegrationEndpoints();
api.MapAttachmentEndpoints();
api.MapFrontendReadEndpoints();
api.MapReportingEndpoints();

app.Run();
