using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace WorkflowPlatform.Api.Data;

public sealed record SqlArgument(string Name, object? Value, SqlDbType? Type = null, int? Size = null, bool IsOutput = false);
public sealed record SqlResults(List<List<Dictionary<string, object?>>> Sets, Dictionary<string, object?> Outputs)
{
    public List<Dictionary<string, object?>> First => Sets.Count > 0 ? Sets[0] : new();
}

public sealed class SqlDatabase(IConfiguration configuration)
{
    private string ConnectionString => configuration.GetConnectionString("Default") is { Length: > 0 } value
        ? value : throw new InvalidOperationException("ConnectionStrings:Default has not been configured.");

    public async Task<SqlConnection> ConnectAsync(CancellationToken ct)
    {
        var connection = new SqlConnection(ConnectionString);
        try { await connection.OpenAsync(ct); return connection; }
        catch { await connection.DisposeAsync(); throw; }
    }

    private static void AddArguments(SqlCommand cmd, IEnumerable<SqlArgument> parameters)
    {
        foreach (var arg in parameters)
        {
            var p = cmd.Parameters.Add("@" + arg.Name, arg.Type ?? SqlDbType.NVarChar);
            if (arg.Size is { } size) p.Size = size;
            if (arg.IsOutput) { p.Direction = arg.Value is null ? ParameterDirection.Output : ParameterDirection.InputOutput; p.Value = arg.Value ?? DBNull.Value; if (arg.Type is null) p.SqlDbType = SqlDbType.BigInt; }
            else { p.Value = arg.Value ?? DBNull.Value; }
        }
    }
    private static async Task<SqlResults> ExecuteAsync(SqlCommand cmd, CancellationToken ct)
    {
        var results = new List<List<Dictionary<string, object?>>>();
        await using (var reader = await cmd.ExecuteReaderAsync(ct))
        {
            do
            {
                if (reader.FieldCount == 0) continue;
                var set = new List<Dictionary<string, object?>>();
                while (await reader.ReadAsync(ct))
                {
                    var item = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
                    for (int i = 0; i < reader.FieldCount; i++)
                    {
                        object? value = await reader.IsDBNullAsync(i, ct) ? null : reader.GetValue(i);
                        item[reader.GetName(i)] = value is byte[] bytes ? Convert.ToBase64String(bytes) : value;
                    }
                    set.Add(item);
                }
                results.Add(set);
            } while (await reader.NextResultAsync(ct));
        }
        var outputs = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        foreach (SqlParameter param in cmd.Parameters)
            if (param.Direction != ParameterDirection.Input)
                outputs[param.ParameterName.TrimStart('@')] = param.Value is DBNull ? null : param.Value;
        return new SqlResults(results, outputs);
    }
    public async Task<SqlResults> ProcedureAsync(string storedProcedure, IEnumerable<SqlArgument> parameters, CancellationToken ct)
    {
        // Only source-code-defined procedure names; never accept an arbitrary SQL name from an HTTP request.
        await using var db = await ConnectAsync(ct);
        await using var cmd = new SqlCommand(storedProcedure, db) { CommandType = CommandType.StoredProcedure, CommandTimeout = 45 };
        AddArguments(cmd, parameters);
        return await ExecuteAsync(cmd, ct);
    }
    public async Task<SqlResults> QueryAsync(string fixedSql, IEnumerable<SqlArgument> args, CancellationToken ct)
    {
        await using var db = await ConnectAsync(ct);
        await using var cmd = new SqlCommand(fixedSql, db) { CommandType = CommandType.Text, CommandTimeout = 30 };
        AddArguments(cmd, args);
        return await ExecuteAsync(cmd, ct);
    }
    public async Task<object?> ScalarAsync(string fixedSql, IEnumerable<SqlArgument> args, CancellationToken ct)
    {
        await using var db = await ConnectAsync(ct);
        await using var cmd = new SqlCommand(fixedSql, db) { CommandType = CommandType.Text, CommandTimeout = 30 };
        AddArguments(cmd, args);
        var obj = await cmd.ExecuteScalarAsync(ct);
        return obj is DBNull ? null : obj;
    }
    public static SqlArgument G(string name, long? value) => new(name, value, SqlDbType.BigInt);
    public static SqlArgument S(string name, string? value) => new(name, value, SqlDbType.NVarChar, -1);
}
