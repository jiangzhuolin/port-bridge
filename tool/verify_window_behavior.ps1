param([Parameter(Mandatory)][string]$Executable)
$ErrorActionPreference = 'Stop'
$appPath = (Resolve-Path -LiteralPath $Executable).Path

# Exercise only windows belonging to the processes launched below. The native
# messages are the same events used by the title bar and tray-manager menu.
Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
public static class BridgeWindowTest {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int command);
  [StructLayout(LayoutKind.Sequential)] public struct IconId {
    public uint size; public IntPtr window; public uint id; public Guid guid;
  }
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int left, top, right, bottom; }
  [DllImport("shell32.dll")] static extern int Shell_NotifyIconGetRect(ref IconId id, out Rect rect);
  public static bool HasTrayIcon(IntPtr window) {
    var id = new IconId { size = (uint)Marshal.SizeOf<IconId>(), window = window, id = 1 };
    return Shell_NotifyIconGetRect(ref id, out var rect) == 0;
  }
}
public sealed class BridgeEchoTest : IDisposable {
  readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
  readonly CancellationTokenSource stop = new CancellationTokenSource();
  public int Port => ((IPEndPoint)listener.LocalEndpoint).Port;
  public BridgeEchoTest() { listener.Start(); _ = Accept(); }
  async Task Accept() {
    try {
      while (!stop.IsCancellationRequested) {
        var client = await listener.AcceptTcpClientAsync(stop.Token);
        _ = Echo(client);
      }
    } catch (OperationCanceledException) { }
  }
  async Task Echo(TcpClient client) {
    using (client) {
      try {
        var stream = client.GetStream(); var buffer = new byte[4096]; int count;
        while ((count = await stream.ReadAsync(buffer.AsMemory(), stop.Token)) != 0)
          await stream.WriteAsync(buffer.AsMemory(0, count), stop.Token);
      } catch (System.IO.IOException) { } catch (OperationCanceledException) { }
    }
  }
  public void Dispose() { stop.Cancel(); listener.Stop(); }
}
'@

function Wait-BridgeCondition([scriptblock]$Condition, [string]$Description) {
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (& $Condition)) {
        if ([DateTime]::UtcNow -gt $deadline) { throw "Timed out: $Description" }
        Start-Sleep -Milliseconds 100
    }
}
function Assert-BridgeEcho($Stream) {
    $payload = [Text.Encoding]::UTF8.GetBytes('window behavior keeps this TCP connection alive')
    $Stream.Write($payload, 0, $payload.Length)
    $received = [byte[]]::new($payload.Length)
    $offset = 0
    while ($offset -lt $received.Length) {
        $count = $Stream.Read($received, $offset, $received.Length - $offset)
        if ($count -eq 0) { throw 'Forwarded connection closed unexpectedly' }
        $offset += $count
    }
    if ([Convert]::ToBase64String($received) -ne [Convert]::ToBase64String($payload)) {
        throw 'Forwarded payload changed'
    }
}

$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $temporaryBase "port-bridge-window-test-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testRoot | Out-Null
$echo = [BridgeEchoTest]::new()
try {
    foreach ($tray in @($false, $true)) {
        foreach ($close in @('exit', 'minimize')) {
            $caseRoot = Join-Path $testRoot "$tray-$close"
            $config = Join-Path $caseRoot 'port-bridge'
            New-Item -ItemType Directory -Path $config -Force | Out-Null
            @{language='zh_CN'; minimize_to_tray=$tray; close_action=$close} |
                ConvertTo-Json | Set-Content -LiteralPath (Join-Path $config 'settings.json') -Encoding utf8
            $reservation = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
            $reservation.Start()
            $listenPort = $reservation.LocalEndpoint.Port
            $reservation.Stop()
            @{version=1; rules=@(@{id='window-test'; name='Window test'; listen_host='127.0.0.1'; listen_port=$listenPort; target_host='127.0.0.1'; target_port=$echo.Port; auto_start=$true})} |
                ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $config 'rules.json') -Encoding utf8
            $start = [Diagnostics.ProcessStartInfo]::new($appPath)
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            # This is the GUI under test; its first frame must be visible so the
            # native minimize/restore assertions can observe actual transitions.
            $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal
            $start.Environment['XDG_CONFIG_HOME'] = $caseRoot
            $process = [Diagnostics.Process]::Start($start)
            $client = $null
            try {
                Wait-BridgeCondition {
                    if ($process.HasExited) { throw "Application exited before showing a window: $($process.ExitCode)" }
                    $process.Refresh(); $process.MainWindowHandle -ne 0
                } 'initial window'
                $window = $process.MainWindowHandle
                if ($tray) {
                    Wait-BridgeCondition { [BridgeWindowTest]::HasTrayIcon($window) } 'registered tray icon'
                }
                $client = [Net.Sockets.TcpClient]::new()
                $client.Connect('127.0.0.1', $listenPort)
                $stream = $client.GetStream()
                $stream.ReadTimeout = 3000
                Assert-BridgeEcho $stream

                [BridgeWindowTest]::PostMessage($window, 0x0112, [IntPtr]0xF020, [IntPtr]0) | Out-Null
                Wait-BridgeCondition {
                    if ($tray) { -not [BridgeWindowTest]::IsWindowVisible($window) }
                    else { [BridgeWindowTest]::IsIconic($window) -and [BridgeWindowTest]::IsWindowVisible($window) }
                } 'native minimize behavior'
                Assert-BridgeEcho $stream
                if ($tray) {
                    [BridgeWindowTest]::PostMessage($window, 0x0401, [IntPtr]1, [IntPtr]0x0202) | Out-Null
                } else {
                    [BridgeWindowTest]::ShowWindowAsync($window, 9) | Out-Null
                }
                Wait-BridgeCondition { [BridgeWindowTest]::IsWindowVisible($window) -and -not [BridgeWindowTest]::IsIconic($window) } 'restore window'
                Assert-BridgeEcho $stream

                [BridgeWindowTest]::PostMessage($window, 0x0010, [IntPtr]0, [IntPtr]0) | Out-Null
                if ($close -eq 'minimize') {
                    Wait-BridgeCondition {
                        if ($tray) { -not [BridgeWindowTest]::IsWindowVisible($window) }
                        else { [BridgeWindowTest]::IsIconic($window) }
                    } 'close minimizes'
                    if ($process.HasExited) { throw 'Close unexpectedly exited' }
                    Assert-BridgeEcho $stream
                    if ($tray) {
                        # The stable native menu command IDs are set in WindowActions.
                        [BridgeWindowTest]::PostMessage($window, 0x0111, [IntPtr]41001, [IntPtr]0) | Out-Null
                        Wait-BridgeCondition { [BridgeWindowTest]::IsWindowVisible($window) } 'tray Show window menu'
                        [BridgeWindowTest]::PostMessage($window, 0x0111, [IntPtr]41002, [IntPtr]0) | Out-Null
                    } else {
                        # This case intentionally has no Quit tray menu; the harness
                        # closes its own process after checking retained forwarding.
                        $process.Kill()
                    }
                }
                Wait-BridgeCondition { $process.HasExited } 'application exit'
                if (($close -eq 'exit' -or $tray) -and $process.ExitCode -ne 0) {
                    throw "Application exited with $($process.ExitCode)"
                }
                try {
                    if ($stream.ReadByte() -ne -1) { throw 'Exit left a forwarded connection open' }
                } catch [System.IO.IOException] {
                    if ($close -ne 'minimize' -or $tray) { throw }
                    # The harness force-stops only the no-tray/minimize case.
                    # A TCP reset is also a closed connection in that case.
                }
                if ($tray -and [BridgeWindowTest]::HasTrayIcon($window)) { throw 'Tray icon survived exit' }
                $reservation.Start()
                $reservation.Stop()
                Write-Output "Passed: tray=$tray, close=$close, TCP survives minimize/restore and closes on exit."
            } finally {
                if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
                if ($client) { $client.Dispose() }
                $process.Dispose()
            }
        }
    }
} finally {
    $echo.Dispose()
    $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path
    if (-not $resolvedTestRoot.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolvedTestRoot) -notlike 'port-bridge-window-test-*') {
        throw 'Refusing cleanup outside the temporary test directory'
    }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}
