namespace WorkflowPlatform.Api.Services;

public static class IntegrationDestinationPolicy
{
    public static bool IsAllowed(Uri uri, IConfiguration config)
    {
        if (uri.UserInfo.Length != 0 || uri.HostNameType != UriHostNameType.Dns ||
            !uri.IdnHost.Contains('.') || uri.IdnHost.EndsWith(".", StringComparison.Ordinal) || uri.IdnHost.TrimEnd('.').Equals("localhost", StringComparison.OrdinalIgnoreCase) ||
            uri.IdnHost.TrimEnd('.').EndsWith(".localhost", StringComparison.OrdinalIgnoreCase)) return false;
        if (uri.Scheme == Uri.UriSchemeHttps && uri.Port == 443) return true;
        if (uri.Port != 5000 && !(uri.Scheme == Uri.UriSchemeHttp && uri.Port == 80)) return false;
        if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) return false;
        if (!string.Equals(config["Integration:Proxy:Mode"] ?? "PinnedIp", "PinnedIp", StringComparison.OrdinalIgnoreCase)) return false;
        return config.GetSection("Integration:ApprovedInternalTargets").GetChildren().Any(x =>
            string.Equals(x["Host"]?.TrimEnd('.'), uri.IdnHost.TrimEnd('.'), StringComparison.OrdinalIgnoreCase) &&
            x.GetSection("AllowedOrigins").Get<string[]>()?.Contains(uri.GetLeftPart(UriPartial.Authority), StringComparer.OrdinalIgnoreCase) == true);
    }
}
