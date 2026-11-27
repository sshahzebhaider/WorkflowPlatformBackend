using System.Net;
using System.Net.Http.Headers;
using System.Net.Security;
using System.Security.Authentication;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using WorkflowPlatform.Api.Data;

namespace WorkflowPlatform.Api.Services;

public sealed record ApiTestResult(int Status, JsonElement Body, Dictionary<string,object?> Mapped, bool HasResponseMappings=false, List<JsonElement>? LodgementRecords=null);

public sealed class OperationTester(IConfiguration config, SqlDatabase db, ILogger<OperationTester> logger)
{
    private static readonly Regex Placeholder = new(@"\{\{\s*([A-Za-z0-9_.]+)\s*\}\}",RegexOptions.Compiled);
    public async Task<ApiTestResult> RunAsync(long operationId, Dictionary<string,JsonElement> inputs,CancellationToken ct,string? idempotencyKey=null,long? projectId=null,bool readOnly=false,bool selectRecords=false,bool diagnosticTest=false)
    {
        if (!config.GetValue<bool>("Integration:Enabled"))
            throw new ArgumentException("REST operation execution is disabled. Configure Integration:Enabled explicitly.");
        var rows=(await db.QueryAsync(@"
SELECT s.DataSourceId,s.BaseUrl,s.Kind,s.CredentialSecretRef,o.HttpMethod,o.UrlPath,o.RequestTemplateJson,o.HeaderTemplateJson,o.ResponseMapJson,o.RequestParamsJson
FROM integration.Operations o JOIN integration.DataSources s ON s.DataSourceId=o.DataSourceId
WHERE o.OperationId=@id AND s.IsActive=1 AND o.IsActive=1",
            new[]{SqlDatabase.G("id",operationId)},ct)).First;
        if (rows.Count==0) throw new ArgumentException("Operation not found or inactive.");
        var op=rows[0];
        if (op["Kind"]?.ToString()!="REST") throw new ArgumentException("Only REST operations support live API testing.");
        var baseUrl=op["BaseUrl"]?.ToString()??"";
        if (!Uri.TryCreate(baseUrl,UriKind.Absolute,out var baseUri) || !IntegrationDestinationPolicy.IsAllowed(baseUri,config))
            throw new ArgumentException("Destination protocol, host or port is not approved by server policy.");
        // Approval is per source and bound to the exact reviewed URL, not a config-file host.
        // An edited URL becomes unapproved immediately without an API restart.
        var approved=await db.ScalarAsync(@"
SELECT COUNT_BIG(*) FROM integration.DataSourceApprovals a
JOIN integration.DataSources s ON s.DataSourceId=a.DataSourceId
WHERE a.DataSourceId=@id AND a.IsApproved=1
 AND a.ApprovedBaseUrl=s.BaseUrl AND a.ApprovedBaseUrl COLLATE Latin1_General_BIN2=@baseUrl COLLATE Latin1_General_BIN2 AND a.ApprovedHost=@host
 AND (@project IS NULL OR EXISTS(SELECT 1 FROM integration.ProjectDataSources p WHERE p.DataSourceId=s.DataSourceId AND p.ProjectId=@project))",
            new[]{SqlDatabase.G("id",Convert.ToInt64(op["DataSourceId"])),SqlDatabase.S("host",baseUri.IdnHost.ToLowerInvariant()),SqlDatabase.S("baseUrl",baseUrl),new SqlArgument("project",projectId,System.Data.SqlDbType.BigInt)},ct);
        if (Convert.ToInt64(approved??0L)!=1)
            throw new ArgumentException("The Data Source host needs Platform Admin approval. Review and approve the saved URL in Data connections.");
        var rawPath=op["UrlPath"]?.ToString()??"";
        if (!rawPath.StartsWith('/') || rawPath.StartsWith("//") || rawPath.Contains("..") || rawPath.Contains('#'))
            throw new ArgumentException("Operation path must be a safe relative path starting with /.");
        var method=(op["HttpMethod"]?.ToString()??"GET").ToUpperInvariant();
        if (method is not ("GET" or "POST" or "PUT" or "PATCH" or "DELETE")) throw new ArgumentException("Unsupported HTTP verb.");
        if (readOnly && method!="GET")
        {
            var approvedReadOnlyPost=method=="POST" && config.GetSection("Integration:ApprovedReadOnlyPostOperations").GetChildren().Any(x =>
                x.GetValue<long>("OperationId")==operationId && string.Equals(x["BaseUrl"],baseUrl,StringComparison.Ordinal) && string.Equals(x["UrlPath"],rawPath,StringComparison.Ordinal));
            // Restore HTTPS POST for the authenticated admin diagnostic endpoints.
            // Intake callers never set diagnosticTest; live intake retains its approval gate.
            var diagnosticPost=method=="POST" && diagnosticTest && !selectRecords && baseUri.Scheme==Uri.UriSchemeHttps;
            var temporaryTestPost=false;
            // Explicit opt-in for sandbox diagnostics and UAT intake only. Never changes Live project rules.
            if (!approvedReadOnlyPost && !diagnosticPost && method=="POST" && baseUri.Scheme==Uri.UriSchemeHttps &&
                config.GetValue<bool>("Integration:AllowTemporaryPostTesting") &&
                config.GetSection("Integration:TemporaryPostTestingBaseUrls").GetChildren().Any(x =>
                    string.Equals(x.Value,baseUrl,StringComparison.Ordinal)))
            {
                // A null project is the authenticated Platform Admin diagnostics endpoint.
                temporaryTestPost=projectId is null || Convert.ToInt64(await db.ScalarAsync(@"
SELECT COUNT_BIG(*) FROM core.Projects WHERE ProjectId=@project AND Status='UAT'",
                    new[]{SqlDatabase.G("project",projectId.Value)},ct)??0L)==1;
                if (temporaryTestPost)
                    logger.LogWarning("Temporary POST testing exception used for operation {OperationId}, project {ProjectId}.",operationId,projectId);
            }
            if (diagnosticPost)
                logger.LogWarning("Admin POST diagnostic executed for operation {OperationId}, project {ProjectId}.",operationId,projectId);
            if (!approvedReadOnlyPost && !diagnosticPost && !temporaryTestPost)
                throw new ArgumentException("Live tests and intake lookups require GET or a server-approved read-only POST operation.");
        }
        if (baseUri.Scheme==Uri.UriSchemeHttp && !string.IsNullOrWhiteSpace(op["CredentialSecretRef"]?.ToString())) throw new ArgumentException("Credentials require HTTPS.");
        var built=RestRequestBuilder.Build(rawPath,op["RequestTemplateJson"]?.ToString(),
            op["RequestParamsJson"]?.ToString(),op["HeaderTemplateJson"]?.ToString(),inputs,method);
        // Keep the configured base URL's /api/v1/ prefix, not just its host.
        if(!string.IsNullOrEmpty(baseUri.Query) || !string.IsNullOrEmpty(baseUri.Fragment))
            throw new ArgumentException("Data source base URL cannot contain a query or fragment.");
        var baseForPaths=new Uri(baseUri.GetLeftPart(UriPartial.Path).TrimEnd('/')+"/");
        var uri=new Uri(baseForPaths,built.Path.TrimStart('/'));
        if (!string.Equals(uri.Host,baseUri.Host,StringComparison.OrdinalIgnoreCase) || uri.Port!=baseUri.Port ||
            uri.Scheme!=baseUri.Scheme || !uri.AbsolutePath.StartsWith(baseForPaths.AbsolutePath,StringComparison.Ordinal))
            throw new ArgumentException("Operation cannot change the approved API host or base path.");
        if (uri.Scheme==Uri.UriSchemeHttp && (built.Headers.Count!=0 || method!="GET"))
            throw new ArgumentException("Plain HTTP is limited to credential-free GET requests without custom headers.");
        // PinnedIp uses DNS-pinned public IPs or reviewed exact internal IPs
        // for individually configured corporate hosts. In explicitly
        // approved CorporateGateway mode, the gateway itself enforces the public-IP
        // policy on its DNS resolution; app checks still require an approved hostname.
        var connectSeconds=Math.Clamp(config.GetValue<int?>("Integration:ConnectTimeoutSeconds")??8,2,30);
        var requestSeconds=Math.Clamp(config.GetValue<int?>("Integration:RequestTimeoutSeconds")??30,10,120);
        // Choose the transport mode BEFORE reading any proxy configuration.
        // A stale Integration:Proxy:Url must never make PinnedIp use a proxy.
        var proxyMode=GetProxyMode(config);
        var proxy=proxyMode=="CorporateGateway" ? GetConfiguredProxy(config) : null;
        logger.LogInformation(
            "REST operation {OperationId}: outbound mode={Mode}, usesCorporateGateway={UsesProxy}.",
            operationId,proxyMode,proxy is not null);
        if (proxyMode=="ApprovedCorporateDns")
        {
            // Host approval is already checked against the exact saved BaseUrl in SQL.
            // Corporate DNS mode allows its vetted RFC1918/ULA answers, but never
            // localhost, literal IPs, link-local or metadata endpoints.
            ValidateApprovedCorporateHost(uri);
        }
        if (proxyMode=="CorporateGateway")
        {
            if (proxy is null)
                throw new ArgumentException("Corporate proxy mode requires Integration:Proxy:Url.");
            if (!config.GetValue<bool>("Integration:Proxy:EnforcesPublicDestinationPolicy"))
                throw new ArgumentException("Corporate gateway mode requires a security-approved proxy that blocks private, loopback, link-local and metadata destinations after DNS resolution. Set Integration:Proxy:EnforcesPublicDestinationPolicy only after that policy is verified.");
            ValidateCorporateDestination(uri);
        }
        JsonElement root;
        int httpStatus;
        try
        {
            (httpStatus,root)=await SendApprovedAsync(
                uri,method,built.BodyJson,built.Headers,op["CredentialSecretRef"]?.ToString(),
                idempotencyKey,operationId,connectSeconds,requestSeconds,proxy,ct);
        }
        catch(OperationCanceledException ex) when (!ct.IsCancellationRequested)
        {
            logger.LogWarning("REST operation {OperationId} timed out contacting approved host {Host} (proxy enabled: {ProxyEnabled}).",
                operationId,baseUri.IdnHost,proxy is not null);
            throw new ArgumentException($"External API timed out after {requestSeconds} seconds. Check server outbound network or proxy settings.",ex);
        }
        catch(HttpRequestException ex)
        {
            // Do not print request URLs, query parameters or credentials into logs.
            logger.LogWarning(
                "REST operation {OperationId} failed reaching approved host {Host}; transport={TransportError}, reason={Reason}, proxyMode={ProxyMode}.",
                operationId,baseUri.IdnHost,ex.HttpRequestError,TransportFailureCategory(ex),proxyMode);
            var message=proxyMode=="CorporateGateway"
                ? "Corporate proxy could not complete the HTTPS request. Check the configured proxy host/port, the API service account's proxy authorization (HTTP 407/CONNECT), and corporate TLS certificates. See API server logs for the transport category."
                : DescribeConnectionFailure(ex,proxy is not null);
            throw new ArgumentException(message,ex);
        }
        catch(IOException ex)
        {
            logger.LogWarning("REST operation {OperationId} stream failed contacting {Host}: {FailureType}.",
                operationId,baseUri.IdnHost,ex.GetType().Name);
            throw new ArgumentException("External API connection closed unexpectedly.",ex);
        }
        catch(SocketException ex)
        {
            logger.LogWarning("REST operation {OperationId} socket failure for {Host}: {SocketError}.",
                operationId,baseUri.IdnHost,ex.SocketErrorCode);
            throw new ArgumentException("External API network connection failed. Check server DNS and outbound HTTPS access.",ex);
        }
        catch(AuthenticationException ex)
        {
            logger.LogWarning("REST operation {OperationId} TLS authentication failed for {Host}.",
                operationId,baseUri.IdnHost);
            throw new ArgumentException("External API or HTTPS proxy certificate could not be validated.",ex);
        }
        var mapped=new Dictionary<string,object?>(StringComparer.OrdinalIgnoreCase);
        var hasResponseMappings=false;
        var definitions=new List<(string? Key,string? Path)>();
        if (op["ResponseMapJson"] is string mappingRaw)
        {
            using var mappings=JsonDocument.Parse(mappingRaw);
            if(mappings.RootElement.ValueKind==JsonValueKind.Array)
            {
                hasResponseMappings=mappings.RootElement.GetArrayLength()>0;
                foreach(var mapping in mappings.RootElement.EnumerateArray())
                {
                    var key=mapping.TryGetProperty("fieldKey",out var k)?k.GetString():null;
                    var source=mapping.TryGetProperty("path",out var p)?p.GetString():null;
                    definitions.Add((key,source));
                    ApplyMapping(mapped,root,key,source);
                }
            }
            else if(mappings.RootElement.ValueKind==JsonValueKind.Object)
            {
                hasResponseMappings=mappings.RootElement.EnumerateObject().Any();
                foreach(var mapping in mappings.RootElement.EnumerateObject())
                {
                    definitions.Add((mapping.Name,mapping.Value.GetString()));
                    ApplyMapping(mapped,root,mapping.Name,mapping.Value.GetString());
                }
            }
        }
        return new ApiTestResult(httpStatus,root,mapped,hasResponseMappings,
            selectRecords ? BuildLodgementRecords(root,definitions,hasResponseMappings) : null);
    }

    /// <summary>
    /// For read-only GET operations, retry the FULL HTTPS exchange on another vetted
    /// destination IP address if a connection or TLS handshake fails. The previous
    /// implementation retried only TCP connect; it could select an IP that accepted
    /// TCP but could not complete TLS, and then never try the remaining addresses.
    /// Mutating verbs are never replayed automatically (a server may have acted).
    /// </summary>
    private async Task<(int Status,JsonElement Body)> SendApprovedAsync(
        Uri uri,string method,string? bodyJson,IReadOnlyDictionary<string,string> headers,
        string? credentialRef,string? idempotencyKey,long operationId,int connectSeconds,
        int requestSeconds,Uri? proxy,CancellationToken ct)
    {
        using var budget=CancellationTokenSource.CreateLinkedTokenSource(ct);
        budget.CancelAfter(TimeSpan.FromSeconds(requestSeconds));
        var token=budget.Token;
        // The trusted corporate gateway is an explicit, administrator-approved egress
        // boundary. Let .NET negotiate CONNECT to the ORIGINAL approved hostname and
        // handle proxy authentication. Do not attempt local DNS pinning in this mode:
        // the gateway may resolve different public IPs than the application server.
        if (proxy is not null && GetProxyMode(config)=="CorporateGateway")
            return await SendThroughCorporateGatewayAsync(
                uri,method,bodyJson,headers,credentialRef,idempotencyKey,
                connectSeconds,proxy,token);
        // Resolve once per request, vet addresses against the selected policy,
        // and pin the socket to one of the resulting IPs. Never let HttpClient
        // resolve a different destination after the security check (DNS rebinding).
        var corporateDnsMode=GetProxyMode(config)=="ApprovedCorporateDns";
        var internalHostApproved=IsConfiguredInternalHost(uri.IdnHost);
        var approvedTargets=corporateDnsMode
            ? await ResolveCorporateTargetsAsync(uri.IdnHost,token)
            : internalHostApproved
                ? await ResolveApprovedInternalTargetsAsync(uri.IdnHost,token)
                : await ResolvePublicTargetsAsync(uri.IdnHost,token);
        // GET is safe to retry on another vetted destination. Mutating methods
        // are attempted exactly once, as their first attempt may have succeeded.
        IPAddress?[] targets=(method=="GET" ? approvedTargets : approvedTargets.Take(1))
            .Select(ip=>(IPAddress?)ip).ToArray();
        for(var i=0;i<targets.Length;i++)
        {
            // Do not let a stalled TLS handshake consume the entire total budget
            // before the next approved IP gets an opportunity. The last address
            // may use the remaining global request budget.
            using var attemptBudget=CancellationTokenSource.CreateLinkedTokenSource(token);
            if(method=="GET" && i+1<targets.Length)
                attemptBudget.CancelAfter(TimeSpan.FromSeconds(Math.Max(connectSeconds+5,10)));
            try
            {
                return await SendOnceAsync(uri,method,bodyJson,headers,credentialRef,
                    idempotencyKey,targets[i],connectSeconds,proxy,
                    corporateDnsMode || internalHostApproved,attemptBudget.Token);
            }
            catch(OperationCanceledException) when(method=="GET" && i+1<targets.Length && !token.IsCancellationRequested)
            {
                logger.LogWarning("REST operation {OperationId}: HTTPS request to approved {AddressFamily} address timed out; trying next vetted address.",
                    operationId,targets[i]!.AddressFamily);
            }
            catch(HttpRequestException ex) when(method=="GET" && i+1<targets.Length && !token.IsCancellationRequested)
            {
                // Log only a failure category and address family, not credentials,
                // request body, full URL, or the submitted user input values.
                logger.LogWarning("REST operation {OperationId}: failed on approved {AddressFamily} endpoint ({Failure}); trying next vetted address.",
                    operationId,targets[i]!.AddressFamily,ex.InnerException?.GetType().Name??ex.GetType().Name);
            }
            catch(IOException ex) when(method=="GET" && i+1<targets.Length && !token.IsCancellationRequested)
            {
                logger.LogWarning("REST operation {OperationId}: approved {AddressFamily} endpoint closed its stream ({Failure}); trying next vetted address.",
                    operationId,targets[i]!.AddressFamily,ex.GetType().Name);
            }
        }
        throw new HttpRequestException("No vetted approved destination completed an HTTPS request.");
    }

    private async Task<(int Status,JsonElement Body)> SendOnceAsync(
        Uri uri,string method,string? bodyJson,IReadOnlyDictionary<string,string> headers,
        string? credentialRef,string? idempotencyKey,IPAddress? pinnedAddress,
        int connectSeconds,Uri? proxy,bool allowReviewedCorporateIp,CancellationToken ct)
    {
        var handler=new SocketsHttpHandler {
            AllowAutoRedirect=false,
            UseCookies=false,
            UseProxy=false,
            ConnectTimeout=TimeSpan.FromSeconds(connectSeconds),
            // This branch is direct-only. CorporateGateway uses the native
            // proxy handler instead; unpinned connections always fail closed.
            ConnectCallback=(context,token)=>pinnedAddress is null
                ? throw new InvalidOperationException("Outbound connection was not pinned to a validated destination.")
                : ConnectPinnedAsync(context.DnsEndPoint,uri.IdnHost,uri.Port,pinnedAddress,
                    connectSeconds,allowReviewedCorporateIp,token)
        };
        return await SendRequestAsync(
            handler,uri,method,bodyJson,headers,credentialRef,idempotencyKey,ct,pinnedAddress);
    }

    // Centralizes all request headers, credential references, HTTP response limits,
    // redirect rejection and JSON parsing for both direct and proxy modes.
    private async Task<(int Status,JsonElement Body)> SendRequestAsync(
        SocketsHttpHandler handler,Uri uri,string method,string? bodyJson,
        IReadOnlyDictionary<string,string> headers,string? credentialRef,
        string? idempotencyKey,CancellationToken ct,IPAddress? pinnedAddress=null)
    {
        using(handler)
        using(var client=new HttpClient(handler,false){Timeout=Timeout.InfiniteTimeSpan})
        using(var request=new HttpRequestMessage(new HttpMethod(method),uri))
        {
            if(uri.Scheme==Uri.UriSchemeHttps && !string.IsNullOrEmpty(idempotencyKey) && idempotencyKey.Length<=140 &&
                idempotencyKey.All(c=>char.IsLetterOrDigit(c)||c is ':' or '-' or '_'))
                request.Headers.TryAddWithoutValidation("X-Idempotency-Key",idempotencyKey);
            if(bodyJson is not null && method!="GET")
                request.Content=new StringContent(bodyJson,Encoding.UTF8,"application/json");
            foreach(var h in headers)
                request.Headers.TryAddWithoutValidation(h.Key,h.Value);
            if(!string.IsNullOrWhiteSpace(credentialRef))
            {
                var parts=credentialRef.Split(':',2);
                if(parts.Length!=2 || !Regex.IsMatch(parts[1],@"^[A-Z][A-Z0-9_]{0,99}$"))
                    throw new ArgumentException("Invalid server credential reference.");
                var secret=config[$"Integration:Secrets:{parts[1]}"];
                if(string.IsNullOrWhiteSpace(secret))
                    throw new ArgumentException($"Integration secret '{parts[1]}' is not configured on this server.");
                if(parts[0].Equals("BEARER",StringComparison.OrdinalIgnoreCase))
                    request.Headers.Authorization=new AuthenticationHeaderValue("Bearer",secret);
                else if(parts[0].Equals("APIKEY",StringComparison.OrdinalIgnoreCase))
                    request.Headers.TryAddWithoutValidation("X-API-Key",secret);
                else throw new ArgumentException("Unsupported integration authentication scheme.");
            }
            using var response=await client.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,ct);
            // Opt-in diagnostics for inconsistent upstream authentication. Never log
            // credentials, request/response bodies, query strings or challenge parameters.
            if(config.GetValue<bool>("Integration:EnableAuthDiagnostics"))
            {
                logger.LogInformation(
                    "REST auth diagnostic: host={Host}, method={Method}, pinnedAddress={PinnedAddress}, status={Status}, authScheme={AuthScheme}, hasApiKey={HasApiKey}, challengeSchemes={ChallengeSchemes}.",
                    uri.IdnHost,method,pinnedAddress?.ToString()??"gateway-managed",
                    (int)response.StatusCode,request.Headers.Authorization?.Scheme??"None",
                    request.Headers.Contains("X-API-Key"),
                    string.Join(",",response.Headers.WwwAuthenticate.Select(x=>x.Scheme)));
            }
            if ((int)response.StatusCode>=300 && (int)response.StatusCode<400)
                throw new ArgumentException("Redirects are not allowed for integration operations.");
            if(!response.IsSuccessStatusCode)
                throw new ArgumentException($"External API returned HTTP {(int)response.StatusCode}.");
            var max=Math.Clamp(config.GetValue<int?>("Integration:MaxResponseBytes")??1048576,1024,1048576);
            if(response.Content.Headers.ContentLength is long size && size>max)
                throw new ArgumentException("External response exceeds configured size limit.");
            await using var stream=await response.Content.ReadAsStreamAsync(ct);
            await using var buffer=new MemoryStream();
            var chunk=new byte[8192]; int read;
            while((read=await stream.ReadAsync(chunk,ct))>0)
            {
                if(buffer.Length+read>max)
                    throw new ArgumentException("External response exceeds configured size limit.");
                await buffer.WriteAsync(chunk.AsMemory(0,read),ct);
            }
            buffer.Position=0;
            try
            {
                using var document=buffer.Length==0
                    ?JsonDocument.Parse("null")
                    :await JsonDocument.ParseAsync(buffer,cancellationToken:ct);
                return ((int)response.StatusCode,document.RootElement.Clone());
            }
            catch(JsonException ex)
            {
                throw new ArgumentException("The approved external API did not return valid JSON.",ex);
            }
        }
    }

    /// <summary>
    /// Enterprise corporate-proxy mode: use the built-in .NET proxy stack instead of
    /// manually issuing CONNECT to a DNS-pinned IP address. Many corporate proxies
    /// require hostname CONNECT and Windows Negotiate/NTLM authentication.
    ///
    /// SECURITY: This mode must only be enabled when the explicitly configured
    /// corporate egress gateway independently rejects private/internal, link-local,
    /// loopback, metadata and other restricted destinations after resolving DNS.
    /// The gateway becomes the destination-IP enforcement boundary; app-level
    /// database approval, hostname checks and TLS validation remain mandatory.
    /// </summary>
    private async Task<(int Status,JsonElement Body)> SendThroughCorporateGatewayAsync(
        Uri uri,string method,string? bodyJson,IReadOnlyDictionary<string,string> headers,
        string? credentialRef,string? idempotencyKey,int connectSeconds,
        Uri proxyUri,CancellationToken ct)
    {
        var webProxy=new WebProxy(proxyUri) { BypassProxyOnLocal=false };
        var defaultCredentials=config.GetValue<bool>("Integration:Proxy:UseDefaultCredentials");
        var username=config["Integration:Proxy:Username"];
        var password=config["Integration:Proxy:Password"];
        var domain=config["Integration:Proxy:Domain"];
        if(defaultCredentials && (!string.IsNullOrWhiteSpace(username) || !string.IsNullOrEmpty(password)))
            throw new ArgumentException("Configure either proxy Windows credentials or explicit proxy credentials, not both.");
        if(defaultCredentials)
        {
            // Restrict transparent Windows credentials to Negotiate/NTLM; never
            // accidentally fall back to Basic over a plaintext HTTP proxy.
            var cache=new CredentialCache();
            cache.Add(proxyUri,"Negotiate",CredentialCache.DefaultNetworkCredentials);
            cache.Add(proxyUri,"NTLM",CredentialCache.DefaultNetworkCredentials);
            webProxy.Credentials=cache;
        }
        else if(!string.IsNullOrWhiteSpace(username))
        {
            if(proxyUri.Scheme!=Uri.UriSchemeHttps || string.IsNullOrWhiteSpace(password))
                throw new ArgumentException("Explicit proxy usernames/passwords require an HTTPS proxy and complete credentials.");
            webProxy.Credentials=new NetworkCredential(username,password,domain);
        }
        else if(!string.IsNullOrWhiteSpace(password))
            throw new ArgumentException("Proxy password was configured without a username.");

        logger.LogInformation("Attempting REST API request through approved corporate egress gateway {ProxyHost} to host {Host}.",
            proxyUri.IdnHost,uri.IdnHost);
        // IMPORTANT: no ConnectCallback. SocketsHttpHandler performs the CONNECT
        // negotiation using the approved hostname, authenticates to the gateway,
        // and checks the destination TLS certificate against uri.IdnHost.
        var handler=new SocketsHttpHandler {
            AllowAutoRedirect=false,
            UseCookies=false,
            UseProxy=true,
            Proxy=webProxy,
            ConnectTimeout=TimeSpan.FromSeconds(connectSeconds)
        };
        return await SendRequestAsync(
            handler,uri,method,bodyJson,headers,credentialRef,idempotencyKey,ct);
    }

    private static string GetProxyMode(IConfiguration config)
    {
        var mode=(config["Integration:Proxy:Mode"]??"PinnedIp").Trim();
        if(mode.Equals("PinnedIp",StringComparison.OrdinalIgnoreCase))return "PinnedIp";
        if(mode.Equals("ApprovedCorporateDns",StringComparison.OrdinalIgnoreCase))return "ApprovedCorporateDns";
        if(mode.Equals("CorporateGateway",StringComparison.OrdinalIgnoreCase))return "CorporateGateway";
        throw new ArgumentException("Integration:Proxy:Mode must be PinnedIp, ApprovedCorporateDns or CorporateGateway.");
    }

    /// <summary>
    /// This opt-in mode is for a deployment where ONLY trusted Platform Admins
    /// can register and approve the exact HTTPS BaseUrl in SQL. DNS is resolved
    /// afresh per request and the socket is pinned to the validated answer.
    /// It does not allow arbitrary IP literals, localhost, metadata or link-local
    /// targets. An IP address is NOT trusted merely because it is reachable.
    /// </summary>
    private static void ValidateApprovedCorporateHost(Uri uri)
    {
        var host=uri.IdnHost.TrimEnd('.').ToLowerInvariant();
        if(uri.Scheme!=Uri.UriSchemeHttps || uri.Port!=443 ||
           IPAddress.TryParse(host,out _) || !host.Contains('.') ||
           host=="localhost" || host.EndsWith(".localhost",StringComparison.Ordinal) ||
           host=="metadata.google.internal")
            throw new ArgumentException(
                "ApprovedCorporateDns requires a Platform Admin-approved HTTPS DNS hostname on port 443; localhost and IP literals are not permitted.");
    }

    private async Task<IPAddress[]> ResolveCorporateTargetsAsync(string host,CancellationToken ct)
    {
        // Resolve once, filter, then pin the TCP socket to exactly one of the
        // filtered DNS answers. No second unvalidated lookup occurs in HttpClient.
        var all=(await Dns.GetHostAddressesAsync(host,ct))
            .Select(NormalizeIp).Distinct().ToArray();
        if(IsConfiguredInternalHost(host)) return await ResolveApprovedInternalTargetsAsync(host,ct);
        // Restore original corporate DNS compatibility for SQL-approved hosts.
        // Explicit per-host IP pins above still take precedence when configured.
        var safe=all.Where(ip=>IsPublic(ip) || IsAllowlistableCorporateIp(ip))
            .OrderBy(ip=>ip.AddressFamily==AddressFamily.InterNetwork?0:1)
            .ToArray();
        logger.LogInformation(
            "REST corporate DNS for approved host {Host}: {SafeCount} public/RFC1918/ULA target(s), {RejectedCount} restricted target(s) excluded.",
            host,safe.Length,all.Length-safe.Length);
        if(safe.Length==0)
            throw new ArgumentException(
                "Approved corporate hostname resolved only to restricted addresses. Loopback, link-local, metadata and other non-approved ranges are blocked.");
        return safe;
    }

    private static void ValidateCorporateDestination(Uri uri)
    {
        var host=uri.IdnHost.TrimEnd('.').ToLowerInvariant();
        // The gateway enforces destination-IP safety after its own DNS lookup.
        // We additionally prevent obviously internal or literal-IP hostnames
        // from entering the trusted-gateway path at all.
        if(uri.Scheme!=Uri.UriSchemeHttps || uri.Port!=443 ||
            IPAddress.TryParse(host,out _) || !host.Contains('.') ||
            new[] {"localhost","local","internal","lan","corp","test","invalid","home.arpa","localdomain"}
                .Any(suffix=>host==suffix || host.EndsWith("."+suffix,StringComparison.Ordinal)))
            throw new ArgumentException("Corporate gateway mode permits only approved external HTTPS domain names. Internal/private destinations require a separately secured connector.");
    }

    private static ValueTask<Stream> ConnectPinnedAsync(
        DnsEndPoint endpoint,string approvedHost,int approvedPort,IPAddress approvedAddress,int connectSeconds,
        bool explicitlyApprovedInternal,CancellationToken ct)
    {
        if(endpoint.Port!=approvedPort || !string.Equals(endpoint.Host,approvedHost,StringComparison.OrdinalIgnoreCase)
            || !(IsPublic(approvedAddress)
                || explicitlyApprovedInternal && IsAllowlistableCorporateIp(approvedAddress)))
            throw new ArgumentException("Connection target does not match a vetted HTTPS destination.");
        // Destination IP is vetted immediately before this call and passed
        // explicitly to the socket. The original URI hostname is preserved for
        // both HTTP Host and TLS SNI/certificate validation.
        return new ValueTask<Stream>(OpenSocketAsync(approvedAddress,approvedPort,connectSeconds,ct));
    }

    // Log safe transport categories only. Do not log full URLs, request bodies,
    // authorization headers or user-supplied query values.
    private static string TransportFailureCategory(Exception exception)
    {
        for(Exception? current=exception;current is not null;current=current.InnerException)
        {
            if(current is SocketException socket)
                return $"socket:{socket.SocketErrorCode}";
            if(current is AuthenticationException)
                return "tls:certificate_or_handshake";
            if(current is OperationCanceledException)
                return "timeout_or_cancellation";
        }
        return exception.GetType().Name;
    }

    // The user-facing message contains only a category, never a URL, token, internal IP,
    // or exception stack trace. Full details are intentionally not logged to avoid leaks.
    private static string DescribeConnectionFailure(HttpRequestException error,bool proxyConfigured)
    {
        for(Exception? cause=error;cause is not null;cause=cause.InnerException)
        {
            if(cause is SocketException socket)
                return socket.SocketErrorCode switch
                {
                    SocketError.TimedOut => "Connection to the approved API timed out. Check outbound TCP 443 and proxy requirements on the API server.",
                    SocketError.NetworkUnreachable or SocketError.HostUnreachable => "The API server cannot reach the approved destination network. Check routing, firewall and VPN/proxy settings.",
                    SocketError.ConnectionRefused => "The outbound connection was refused. Check the destination port and any configured proxy.",
                    SocketError.HostNotFound or SocketError.NoData => "The approved API hostname could not be resolved. Check DNS on the API server.",
                    _ => "Outbound API connection failed. Check the API server log for the socket error code."
                };
            if(cause is OperationCanceledException)
                return "Connecting to the approved API timed out. Check outbound routing and configured connection timeout.";
        }
        return proxyConfigured
            ? "The configured outbound proxy could not establish the approved HTTPS tunnel. Check proxy connectivity and CONNECT authorization on the API server."
            : "No approved HTTPS destination was reachable. Check API server routing, DNS and TLS settings.";
    }

    /// <summary>
    /// Optional explicitly configured outbound proxy. No system/browser proxy is
    /// implicitly trusted. PinnedIp mode uses the legacy IP-address CONNECT tunnel;
    /// CorporateGateway mode uses .NET's native hostname CONNECT and Windows auth.
    /// Proxy credentials must be stored in secrets, not URLs or source control.
    /// </summary>
    private static Uri? GetConfiguredProxy(IConfiguration config)
    {
        var raw=config["Integration:Proxy:Url"];
        if(string.IsNullOrWhiteSpace(raw))return null;
        if(!Uri.TryCreate(raw,UriKind.Absolute,out var proxy)
            || proxy.Scheme is not ("http" or "https")
            || string.IsNullOrWhiteSpace(proxy.Host) || proxy.UserInfo.Length>0
            || proxy.AbsolutePath!="/" || proxy.Query.Length>0 || proxy.Fragment.Length>0)
            throw new ArgumentException("Integration:Proxy:Url must be an HTTP(S) proxy endpoint without embedded credentials, path, or query.");
        if(!string.IsNullOrEmpty(config["Integration:Proxy:Username"]) && proxy.Scheme!="https")
            throw new ArgumentException("Authenticated integration proxies require HTTPS. Configure an HTTPS proxy endpoint.");
        return proxy;
    }

    /// <summary>
    /// Opt-in for an EXACT corporate HTTPS hostname whose DNS resolves to a private
    /// address. Public hosts retain normal PinnedIp handling. This is not a blanket
    /// private-network exception: the administrator
    /// must pin exact RFC1918/ULA addresses in Integration:ApprovedInternalTargets.
    /// A resolved address that is not in that list is never contacted. The data
    /// source's separate Platform Admin host approval is still required.
    /// </summary>
    private bool IsConfiguredInternalHost(string host) =>
        config.GetSection("Integration:ApprovedInternalTargets").GetChildren()
            .Any(x=>string.Equals((x["Host"]??"").TrimEnd('.'),host.TrimEnd('.'),
                StringComparison.OrdinalIgnoreCase));

    private async Task<IPAddress[]> ResolveApprovedInternalTargetsAsync(string host,CancellationToken ct)
    {
        host=host.TrimEnd('.').ToLowerInvariant();
        // IP-literal URLs, localhost and wildcard/short hostnames are deliberately
        // not supported, even when an administrator attempts to configure them.
        if(IPAddress.TryParse(host,out _) || !host.Contains('.') ||
           host=="localhost" || host.EndsWith(".localhost",StringComparison.Ordinal))
            throw new ArgumentException("ApprovedInternal requires a named HTTPS host, not an IP literal or localhost.");

        var matches=config.GetSection("Integration:ApprovedInternalTargets").GetChildren()
            .Where(x=>string.Equals((x["Host"]??"").TrimEnd('.'),host,
                StringComparison.OrdinalIgnoreCase)).ToArray();
        if(matches.Length!=1)
            throw new ArgumentException("The API host is not uniquely configured under Integration:ApprovedInternalTargets. Ask IT to approve an exact host and IP.");

        var configured=matches[0].GetSection("Addresses").GetChildren()
            .Select(x=>x.Value?.Trim()).ToArray();
        if(configured.Length is <1 or >8 || configured.Any(string.IsNullOrWhiteSpace))
            throw new ArgumentException("ApprovedInternal requires 1-8 exact approved private IP addresses for the named host.");
        var pinned=new HashSet<IPAddress>();
        foreach(var raw in configured)
        {
            if(!IPAddress.TryParse(raw,out var parsed))
                throw new ArgumentException("ApprovedInternal contains an invalid IP address.");
            parsed=NormalizeIp(parsed);
            if(!IsAllowlistableCorporateIp(parsed))
                throw new ArgumentException("ApprovedInternal permits only individually reviewed RFC1918/ULA addresses; not loopback, metadata, link-local, public or reserved addresses.");
            if(!pinned.Add(parsed))
                throw new ArgumentException("ApprovedInternal contains duplicate IP entries.");
        }

        var dns=(await Dns.GetHostAddressesAsync(host,ct))
            .Select(NormalizeIp).Distinct().ToArray();
        var targets=dns.Where(pinned.Contains)
            .OrderBy(ip=>ip.AddressFamily==AddressFamily.InterNetwork?0:1)
            .ToArray();
        logger.LogInformation("REST approved-internal DNS policy for {Host}: {AllowedCount} exact approved address(es) matched, {OtherCount} DNS answer(s) ignored.",
            host,targets.Length,dns.Length-targets.Length);
        if(targets.Length==0)
            throw new ArgumentException("ApprovedInternal host DNS did not match its reviewed IP allowlist. Verify the hostname and exact IPs with your network team; no request was sent.");
        return targets;
    }

    private static IPAddress NormalizeIp(IPAddress ip) => ip.IsIPv4MappedToIPv6 ? ip.MapToIPv4() : ip;

    // Corporate private addresses only; explicitly excludes loopback, link-local,
    // multicast, unspecified, CGNAT, benchmark and cloud metadata destinations.
    private static bool IsAllowlistableCorporateIp(IPAddress address)
    {
        var ip=NormalizeIp(address);
        if(IPAddress.IsLoopback(ip) || ip.Equals(IPAddress.Any) || ip.Equals(IPAddress.IPv6Any))
            return false;
        var b=ip.GetAddressBytes();
        if(ip.AddressFamily==AddressFamily.InterNetwork)
            return b[0]==10 || b[0]==172 && b[1]>=16 && b[1]<=31 ||
                   b[0]==192 && b[1]==168;
        // IPv6 ULA fc00::/7. Link-local fe80::/10 is not included.
        return ip.AddressFamily==AddressFamily.InterNetworkV6 && (b[0]&0xfe)==0xfc;
    }

    /// <summary>
    /// Resolve an approved hostname to addresses that are safe to dial. DNS can legitimately
    /// return a mix of address types; unsafe candidates are NEVER connected to. The final
    /// socket is pinned to a vetted public IP so a subsequent DNS change cannot redirect it
    /// to a private/loopback/link-local destination.
    /// </summary>
    private async Task<IPAddress[]> ResolvePublicTargetsAsync(string host,CancellationToken ct)
    {
        var all=(await Dns.GetHostAddressesAsync(host,ct)).Distinct().ToArray();
        var safe=all.Where(IsPublic)
            .OrderBy(ip=>ip.AddressFamily==AddressFamily.InterNetwork?0:1)
            .ToArray();
        if(all.Length>safe.Length)
            logger.LogWarning(
                "Approved REST host {Host}: ignored {RejectedCount} private/reserved DNS answers; {ApprovedCount} public candidates remain.",
                host,all.Length-safe.Length,safe.Length);
        if(safe.Length==0)
            throw new ArgumentException(
                "The approved API hostname has no public IP address available. Check the API server's DNS results; private/internal destinations require a separately secured connector.");
        return safe;
    }

    /// <summary>
    /// Each new connection resolves the approved destination, selects only vetted public
    /// addresses and dials those IPs directly, never letting a later resolver choose the
    /// socket destination. Certificate hostname verification still uses the approved URL.
    /// </summary>
    private async ValueTask<Stream> ConnectApprovedAsync(DnsEndPoint endpoint,Uri? proxy,
        int connectSeconds,IConfiguration config,CancellationToken ct)
    {
        if(endpoint.Port!=443)throw new ArgumentException("Integration destination must use HTTPS port 443.");
        var targets=await ResolvePublicTargetsAsync(endpoint.Host,ct);
        IPAddress[] proxyIps=[];
        if(proxy is not null)
        {
            proxyIps=(await Dns.GetHostAddressesAsync(proxy.IdnHost,ct)).Distinct().ToArray();
            if(proxyIps.Length==0)throw new HttpRequestException("Configured proxy hostname did not resolve.");
        }
        Exception? last=null;
        foreach(var target in targets)
        {
            var connectAddresses=proxy is null ? new[]{target}:proxyIps;
            foreach(var address in connectAddresses)
            {
                ct.ThrowIfCancellationRequested();
                try
                {
                    if(proxy is null)
                        return await OpenSocketAsync(address,endpoint.Port,connectSeconds,ct);
                    return await OpenProxyTunnelAsync(proxy,address,target,endpoint.Port,connectSeconds,config,ct);
                }
                catch(Exception ex) when (!ct.IsCancellationRequested && ex is (SocketException
                    or HttpRequestException or IOException or OperationCanceledException))
                {
                    last=ex; // Try the next vetted IPv4/IPv6 destination.
                }
            }
        }
        throw new HttpRequestException("No approved public destination address was reachable.",last);
    }

    private static async Task<Stream> OpenSocketAsync(IPAddress address,int port,int connectSeconds,CancellationToken ct)
    {
        var socket=new Socket(address.AddressFamily,SocketType.Stream,ProtocolType.Tcp){NoDelay=true};
        try
        {
            using var timeout=CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(connectSeconds));
            await socket.ConnectAsync(new IPEndPoint(address,port),timeout.Token);
            return new NetworkStream(socket,ownsSocket:true);
        }
        catch { socket.Dispose(); throw; }
    }

    /// <summary>
    /// CONNECT is addressed to the already-vetted public destination IP, not the hostname.
    /// HttpClient still authenticates the ultimate TLS certificate against the ORIGINAL
    /// approved hostname (SNI). A proxy cannot silently redirect resolution to 10.x etc.
    /// Supports an unauthenticated HTTP CONNECT proxy or Basic auth over an HTTPS proxy.
    /// Other proxy authentication schemes (e.g. NTLM) need a separate secure egress gateway.
    /// </summary>
    private static async Task<Stream> OpenProxyTunnelAsync(Uri proxy,IPAddress proxyIp,
        IPAddress target,int targetPort,int connectSeconds,IConfiguration config,CancellationToken ct)
    {
        Stream stream=await OpenSocketAsync(proxyIp,proxy.Port,connectSeconds,ct);
        try
        {
            if(proxy.Scheme=="https")
            {
                var tls=new SslStream(stream,leaveInnerStreamOpen:false);
                stream=tls;
                await tls.AuthenticateAsClientAsync(new SslClientAuthenticationOptions {
                    TargetHost=proxy.IdnHost,
                    EnabledSslProtocols=SslProtocols.None
                },ct);
            }
            var authority=target.AddressFamily==AddressFamily.InterNetworkV6
                ?$"[{target}]:{targetPort}" :$"{target}:{targetPort}";
            var username=config["Integration:Proxy:Username"];
            var password=config["Integration:Proxy:Password"];
            var proxyAuth="";
            if(!string.IsNullOrEmpty(username))
            {
                if(string.IsNullOrEmpty(password) || proxy.Scheme!="https")
                    throw new ArgumentException("An authenticated proxy requires credentials and an HTTPS proxy URL.");
                var encoded=Convert.ToBase64String(Encoding.UTF8.GetBytes($"{username}:{password}"));
                proxyAuth=$"Proxy-Authorization: Basic {encoded}\r\n";
            }
            var connectRequest=$"CONNECT {authority} HTTP/1.1\r\nHost: {authority}\r\n"+
                proxyAuth+"Proxy-Connection: Keep-Alive\r\n\r\n";
            await stream.WriteAsync(Encoding.ASCII.GetBytes(connectRequest),ct);
            await stream.FlushAsync(ct);
            var header=new List<byte>(256);
            var single=new byte[1];
            while(header.Count<8192)
            {
                if(await stream.ReadAsync(single.AsMemory(0,1),ct)==0)
                    throw new HttpRequestException("Proxy closed the CONNECT handshake.");
                header.Add(single[0]);
                var n=header.Count;
                if(n>=4 && header[n-4]==13 && header[n-3]==10 && header[n-2]==13 && header[n-1]==10)
                    break;
            }
            if(header.Count>=8192)throw new HttpRequestException("Proxy CONNECT headers exceed limit.");
            var line=Encoding.ASCII.GetString(header.ToArray()).Split("\r\n",2)[0];
            if(!line.StartsWith("HTTP/1.",StringComparison.Ordinal) ||
                !Regex.IsMatch(line,@"^HTTP/1\.[01] 200(?: |$)"))
                throw new HttpRequestException("Configured proxy did not authorize the HTTPS CONNECT tunnel.");
            return stream;
        }
        catch { await stream.DisposeAsync(); throw; }
    }

    // Only one unambiguous record array may drive a lodgement selection.
    // Explicit paths keep their existing semantics for workflow execution and testing.
    private static List<JsonElement>? BuildLodgementRecords(JsonElement root,List<(string? Key,string? Path)> definitions,bool explicitMappings)
    {
        const int maxRecords=25;
        if(explicitMappings)
        {
            var indexed=new List<(string? Key,string Path,Match Index)>();
            foreach(var (key,path) in definitions)
            {
                if(string.IsNullOrWhiteSpace(path))continue;
                var normalized=Regex.Replace(path.Trim().TrimStart('$').TrimStart('.'),@"\[(\d+)\]",".$1").TrimStart('.');
                var match=Regex.Match(normalized,@"(?:^|\.)(\d+)(?=\.|$)");
                if(match.Success)indexed.Add((key,normalized,match));
            }
            if(indexed.Count==0)return null;
            string Prefix((string? Key,string Path,Match Index) entry)=>entry.Path[..entry.Index.Index];
            var prefix=Prefix(indexed[0]);
            if(indexed.Any(x=>!Prefix(x).Equals(prefix,StringComparison.OrdinalIgnoreCase)))
                throw new ArgumentException("Map fields from one response record array for case lodgement.");
            var array=LodgementIntegration.ExpandJsonString(root);
            if(prefix.Length>0)
            {
                var probe=new Dictionary<string,object?>();
                ApplyMapping(probe,root,"records",prefix.TrimEnd('.'));
                if(!probe.TryGetValue("records",out var value)||value is not JsonElement element)return null;
                array=LodgementIntegration.ExpandJsonString(element);
            }
            if(array.ValueKind!=JsonValueKind.Array||array.GetArrayLength()<1)return null;
            if(array.GetArrayLength()>maxRecords)throw new ArgumentException("The lookup returned more than 25 records. Refine the search inputs.");
            if(array.EnumerateArray().Any(x=>x.ValueKind!=JsonValueKind.Object))return null;
            var records=new List<JsonElement>();
            for(var i=0;i<array.GetArrayLength();i++)
            {
                var row=new Dictionary<string,object?>(StringComparer.OrdinalIgnoreCase);
                foreach(var (key,path) in definitions)
                {
                    var entry=indexed.FirstOrDefault(x=>x.Key==key && x.Path==Regex.Replace((path??"").Trim().TrimStart('$').TrimStart('.'),@"\[(\d+)\]",".$1").TrimStart('.'));
                    var actual=entry.Index is null ? path : entry.Path[..entry.Index.Groups[1].Index]+i.ToString(System.Globalization.CultureInfo.InvariantCulture)+entry.Path[(entry.Index.Groups[1].Index+entry.Index.Groups[1].Length)..];
                    ApplyMapping(row,root,key,actual);
                }
                records.Add(JsonSerializer.SerializeToElement(row));
            }
            return records;
        }
        var arrays=new List<JsonElement>();
        void Walk(JsonElement value,int depth)
        {
            if(depth>8||arrays.Count>1)return;
            value=LodgementIntegration.ExpandJsonString(value);
            if(value.ValueKind==JsonValueKind.Array && value.GetArrayLength()>0 && value.EnumerateArray().All(x=>x.ValueKind==JsonValueKind.Object))arrays.Add(value);
            else if(value.ValueKind==JsonValueKind.Object)foreach(var prop in value.EnumerateObject())Walk(prop.Value,depth+1);
        }
        Walk(root,0);
        if(arrays.Count!=1||arrays[0].GetArrayLength()<1)return null;
        if(arrays[0].GetArrayLength()>maxRecords)throw new ArgumentException("The lookup returned more than 25 records. Refine the search inputs.");
        return arrays[0].EnumerateArray().Select(x=>x.Clone()).ToList();
    }

    private static void ApplyMapping(Dictionary<string,object?> target,JsonElement root,string? key,string? path)
    {
        key=key?.Trim(); path=path?.Trim();
        if(string.IsNullOrWhiteSpace(key)||!Regex.IsMatch(key,@"^[A-Za-z0-9_]{1,100}$")||
            key.Equals("api_response",StringComparison.OrdinalIgnoreCase)||
            new[]{"__proto__","constructor","prototype"}.Contains(key,StringComparer.OrdinalIgnoreCase)||
            string.IsNullOrWhiteSpace(path)||path.Length>1000) return;
        // Accept the same bracket-index paths shown by the response preview, plus dotted indexes.
        if(path.StartsWith("$."))path=path[2..];
        else if(path.StartsWith("$["))path=path[1..];
        path=Regex.Replace(path,@"\[(\d+)\]",".$1");
        if(path.StartsWith('.'))path=path[1..];
        var parts=path.Split('.');
        if(parts.Length>32||parts.Any(string.IsNullOrWhiteSpace))return;
        var current=root;
        foreach(var part in parts)
        {
            current=LodgementIntegration.ExpandJsonString(current);
            if(current.ValueKind==JsonValueKind.Array && int.TryParse(part,out var index) && index>=0 && index<current.GetArrayLength())
                current=current[index];
            else if(current.ValueKind==JsonValueKind.Object && current.TryGetProperty(part,out var next))current=next;
            else if(current.ValueKind==JsonValueKind.Object)
            {
                var candidates=current.EnumerateObject().Where(p=>p.Name.Equals(part,StringComparison.OrdinalIgnoreCase)).Take(2).ToArray();
                if(candidates.Length!=1)return;
                current=candidates[0].Value;
            }
            else return;
        }
        target[key]=current.Clone();
    }

    private static string Expand(string text,Dictionary<string,JsonElement> inputs,bool escape)
    {
        return Placeholder.Replace(text,match=>
        {
            JsonElement value=default;
            var key=match.Groups[1].Value;
            if (!inputs.TryGetValue(key,out value) || value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
                throw new ArgumentException($"Missing required integration input '{key}'.");
            var str=value.ValueKind==JsonValueKind.String?value.GetString()??"":value.ToString();
            if(str.Length>300)throw new ArgumentException("Integration input is too long.");
            return escape?Uri.EscapeDataString(str):str;
        });
    }
    private static string ExpandJson(string template,Dictionary<string,JsonElement> inputs)
    {
        using var doc=JsonDocument.Parse(template);
        object? ConvertValue(JsonElement e)
        {
            if(e.ValueKind==JsonValueKind.Object)return e.EnumerateObject().ToDictionary(x=>x.Name,x=>ConvertValue(x.Value));
            if(e.ValueKind==JsonValueKind.Array)return e.EnumerateArray().Select(ConvertValue).ToArray();
            if(e.ValueKind==JsonValueKind.String)return Expand(e.GetString()??"",inputs,false);
            return JsonSerializer.Deserialize<object>(e.GetRawText());
        }
        return JsonSerializer.Serialize(ConvertValue(doc.RootElement));
    }
    private static bool IsPublic(IPAddress ip)
    {
        if(IPAddress.IsLoopback(ip) || ip.Equals(IPAddress.Any) || ip.Equals(IPAddress.IPv6Any))return false;
        if(ip.IsIPv4MappedToIPv6)ip=ip.MapToIPv4();
        if(ip.AddressFamily==AddressFamily.InterNetwork)
        {
            var b=ip.GetAddressBytes();
            // Deny RFC1918, loopback, link-local, CGNAT, benchmarking, multicast,
            // TEST-NET ranges, protocol assignments and other reserved destinations.
            if(b[0]==0 || b[0]==10 || b[0]==127 || b[0]>=224 ||
               b[0]==169 && b[1]==254 ||
               b[0]==172 && b[1]>=16 && b[1]<=31 ||
               b[0]==192 && (b[1]==168 || b[1]==0 || b[1]==2 || b[1]==88 && b[2]==99) ||
               b[0]==100 && b[1]>=64 && b[1]<=127 ||
               b[0]==198 && (b[1]==18 || b[1]==19 || b[1]==51 && b[2]==100) ||
               b[0]==203 && b[1]==0 && b[2]==113)
                return false;
            return true;
        }
        if(ip.AddressFamily==AddressFamily.InterNetworkV6)
        {
            var b=ip.GetAddressBytes();
            // Restrict to global unicast 2000::/3, excluding documentation and
            // address-transition ranges. ULA, link-local and IPv4-mapped are denied.
            return (b[0]&0xe0)==0x20 &&
                !(b[0]==0x20 && b[1]==0x01 && b[2]==0x0d && b[3]==0xb8) &&
                !(b[0]==0x20 && b[1]==0x01 && b[2]==0 && b[3]==0) &&
                !(b[0]==0x20 && b[1]==0x02);
        }
        return false;
    }
}
