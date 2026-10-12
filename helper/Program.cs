using System.Text;
using Enhance.Helper;

Console.InputEncoding = new UTF8Encoding(false);
Console.OutputEncoding = new UTF8Encoding(false);
using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) => {
    eventArgs.Cancel = true;
    cancellation.Cancel();
};
return await HelperHost.RunAsync(Console.In, Console.Out, args, new DriverExecutor(), cancellation.Token);
