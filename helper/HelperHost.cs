using System.Text;
using System.Text.Json;

namespace Enhance.Helper;

public static class HelperHost
{
    public static async Task<int> RunAsync(TextReader input, TextWriter output, string[] args,
        IQueryExecutor executor, CancellationToken cancellationToken = default)
    {
        if (args.Length == 1 && args[0] == "--version") {
            await output.WriteLineAsync(JsonSerializer.Serialize(new {
                protocol = HelperProtocol.Version, helperVersion = "1.1.1"
            }, HelperProtocol.JsonOptions));
            return 0;
        }

        HelperResponse response;
        try {
            if (args.Length != 0) throw new InvalidRequestException();
            var text = new StringBuilder();
            var buffer = new char[4096];
            int count;
            while ((count = await input.ReadAsync(buffer.AsMemory(), cancellationToken)) > 0) {
                if (text.Length + count > 16 * 1024 * 1024) throw new InvalidRequestException();
                text.Append(buffer, 0, count);
            }
            var request = JsonSerializer.Deserialize<HelperRequest>(text.ToString(), HelperProtocol.JsonOptions);
            if (request is null || !request.IsValid()) throw new InvalidRequestException();
            response = await executor.ExecuteAsync(request, cancellationToken);
        }
        catch (Exception error) when (error is JsonException or InvalidRequestException) {
            response = Failure("invalid_request", "Expected a valid protocol-1 request on stdin; command-line input is not accepted.");
        }
        catch (OperationCanceledException) {
            response = Failure("cancelled", "Query execution was cancelled.");
        }
        catch (UnsupportedValueException) {
            response = Failure("unsupported_value", "A result contains a SQL type that this helper cannot encode safely.");
        }
        catch (Exception) {
            // Never echo arbitrary exceptions, connection strings, SQL, or request bodies.
            response = Failure("internal_error", "SQL Server helper execution failed.");
        }
        await output.WriteLineAsync(JsonSerializer.Serialize(response, HelperProtocol.JsonOptions));
        return response.Ok ? 0 : 1;
    }

    private static HelperResponse Failure(string kind, string message) => new() {
        Errors = new() { new HelperError(kind, message) }
    };
    private sealed class InvalidRequestException : Exception;
}
