using System.Text.Json;
using System.Text.Json.Serialization;

namespace Enhance.Helper;

/// <summary>One stdin request, one stdout JSON response; no SQL or credentials in argv.</summary>
public static class HelperProtocol
{
    public const int Version = 1;
    public static readonly JsonSerializerOptions JsonOptions = new() {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };
}

public sealed record ConnectionOptions
{
    public required string Server { get; init; }
    public required string Database { get; init; }
    public string? User { get; init; }
    public string? Password { get; init; }
    public int? Port { get; init; }
    public string? SslMode { get; init; }
    public bool TrustServerCertificate { get; init; }
    public int ConnectTimeoutSeconds { get; init; } = 15;
}

public sealed record HelperRequest
{
    public required int Protocol { get; init; }
    public string DbType { get; init; } = "sqlserver";
    public required string Query { get; init; }
    public required ConnectionOptions Connection { get; init; }
    public int CommandTimeoutSeconds { get; init; } = 240;

    public bool IsValid() => Protocol == HelperProtocol.Version && DbType is "sqlserver" or "mysql" && !string.IsNullOrWhiteSpace(Query)
        && Connection is not null && !string.IsNullOrWhiteSpace(Connection.Server)
        && !string.IsNullOrWhiteSpace(Connection.Database)
        && (Connection.User is null || !string.IsNullOrWhiteSpace(Connection.User))
        && (Connection.Password is null || Connection.User is not null)
        && (Connection.Port is null || Connection.Port is >= 1 and <= 65535)
        && (Connection.SslMode is null || Connection.SslMode is "disable" or "prefer" or "require" or "verify-ca" or "verify-full")
        && (DbType != "mysql" || !Connection.TrustServerCertificate)
        && Connection.ConnectTimeoutSeconds is >= 1 and <= 300
        && CommandTimeoutSeconds is >= 1 and <= 86400;
}

/// <summary>Columns are positional: duplicate/empty names never become JSON object keys.</summary>
public sealed record ResultColumn(string Name, string Type);
public sealed class ResultSet
{
    public List<ResultColumn> Columns { get; set; } = new();
    public List<string?[]> Rows { get; set; } = new();
}

public sealed record HelperError(string Kind, string Message, int? Number = null,
    int? Severity = null, int? State = null, int? Line = null, string? SqlState = null);
public sealed record HelperMessage(string Message, int Number, int Severity, int State, int Line);

public sealed class HelperResponse
{
    public int Protocol { get; set; } = HelperProtocol.Version;
    public bool Ok { get; set; }
    public List<ResultSet> ResultSets { get; set; } = new();
    public List<HelperMessage> Messages { get; set; } = new();
    public List<HelperError> Errors { get; set; } = new();
    public int? AffectedRows { get; set; }
    public double DurationMs { get; set; }
}

public interface IQueryExecutor
{
    Task<HelperResponse> ExecuteAsync(HelperRequest request, CancellationToken cancellationToken);
}
