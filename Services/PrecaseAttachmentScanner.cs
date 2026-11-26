using System.Diagnostics;
using System.Security.Cryptography;

namespace WorkflowPlatform.Api.Services;

/// <summary>Fail closed. The API does not stage file references without a successful AV scan.</summary>
public sealed class PrecaseAttachmentScanner(IConfiguration config)
{
    public async Task ScanAsync(string path,CancellationToken ct)
    {
        var mode=config["Files:ScanMode"];
        if(!string.Equals(mode,"ClamAV",StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Pre-case attachments require Files:ScanMode=ClamAV and a configured scanner.");
        using var process=new Process();
        process.StartInfo=new ProcessStartInfo(config["Files:ClamScanExecutable"]??"clamscan")
            {UseShellExecute=false,CreateNoWindow=true,RedirectStandardError=true,RedirectStandardOutput=true};
        process.StartInfo.ArgumentList.Add("--no-summary");
        process.StartInfo.ArgumentList.Add("--");
        process.StartInfo.ArgumentList.Add(path);
        if(!process.Start())throw new IOException("Malware scanner failed to start.");
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(90));
        try {await process.WaitForExitAsync(timeout.Token);}
        catch(OperationCanceledException)
        {
            if(!process.HasExited)process.Kill(entireProcessTree:true);
            throw;
        }
        if(process.ExitCode!=0)throw new InvalidOperationException(
            process.ExitCode==1?"Malware detected in uploaded file.":"Malware scanner failed; the file was not accepted.");
    }
}
