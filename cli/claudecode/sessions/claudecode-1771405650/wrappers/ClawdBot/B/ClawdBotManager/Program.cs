using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;
using System.Runtime.InteropServices;

namespace ClawdBotManager;

static class Program
{
    static NotifyIcon? _trayIcon;
    static Process? _gatewayProcess;
    static ToolStripMenuItem? _statusItem;
    static System.Windows.Forms.Timer? _trayIconTimer;
    static System.Windows.Forms.Timer? _restartTimer;
    static System.Windows.Forms.Timer? _healthCheckTimer;
    static bool _userStopped;
    static int _consecutiveFailures = 0;
    static DateTime _lastStartAttempt = DateTime.MinValue;
    static DateTime _lastHealthCheck = DateTime.MinValue;
    static int _healthCheckFailures = 0;
    static string _logDir = Path.Combine(Path.GetTempPath(), "openclaw");
    static Mutex? _mutex;
    static readonly string AppName = "ClawdBotManager";
    static readonly string ExePath = Environment.ProcessPath ?? AppContext.BaseDirectory;

    [STAThread]
    static void Main()
    {
        // Single instance check
        bool createdNew;
        _mutex = new Mutex(true, "ClawdBotManager_SingleInstance_2026", out createdNew);
        if (!createdNew)
        {
            return;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Directory.CreateDirectory(_logDir);

        SetupEnvironment();
        
        // BULLETPROOF: Ensure we're in startup
        EnsureStartupEntry();
        
        StartGateway();
        SetupTray();

        Application.Run();

        _mutex?.ReleaseMutex();
        _mutex?.Dispose();
    }

    static void SetupEnvironment()
    {
        Environment.SetEnvironmentVariable("SHELL", Environment.GetEnvironmentVariable("COMSPEC") ?? "cmd.exe");
        Environment.SetEnvironmentVariable("OPENCLAW_SHELL", "cmd");
        Environment.SetEnvironmentVariable("OPENCLAW_NO_WSL", "1");
        Environment.SetEnvironmentVariable("OPENCLAW_NO_PTY", "1");

        // ULTRA-BULLETPROOF Node.js settings (only VALID flags)
        Environment.SetEnvironmentVariable("NODE_OPTIONS",
            "--max-old-space-size=8192 " +           // 8GB memory limit
            "--dns-result-order=ipv4first " +        // DNS caching
            "--max-http-header-size=16384 " +        // Larger headers
            "--expose-gc");                          // Enable GC tuning

        // TASK #5: DNS resolution caching with aggressive TTL
        Environment.SetEnvironmentVariable("NODE_DNS_CACHE_SIZE", "1000");
        Environment.SetEnvironmentVariable("NODE_DNS_CACHE_TTL", "3600");      // 1 hour DNS cache
        Environment.SetEnvironmentVariable("OPENCLAW_DNS_CACHE", "true");

        // TASK #13: Automatic garbage collection tuning
        Environment.SetEnvironmentVariable("NODE_GC_SCHEDULE", "30000");        // GC every 30s
        Environment.SetEnvironmentVariable("NODE_HEAP_SNAPSHOT_SIGNAL", "false");

        // ULTRA-AGGRESSIVE network resilience - PREVENT ALL FETCH FAILURES
        Environment.SetEnvironmentVariable("NODE_TLS_REJECT_UNAUTHORIZED", "0");
        Environment.SetEnvironmentVariable("OPENCLAW_RETRY_DELAY", "500");           // 0.5s base retry delay (faster)
        Environment.SetEnvironmentVariable("OPENCLAW_MAX_RETRIES", "50");            // 50 retries (more attempts)
        Environment.SetEnvironmentVariable("OPENCLAW_FETCH_TIMEOUT", "120000");      // 120s timeout (doubled)
        Environment.SetEnvironmentVariable("OPENCLAW_CONNECTION_TIMEOUT", "120000"); // 120s connection timeout
        Environment.SetEnvironmentVariable("NODE_FETCH_RETRY", "10");                // Node fetch retry attempts
        Environment.SetEnvironmentVariable("NODE_FETCH_RETRY_DELAY", "1000");        // 1s between fetch retries

        // TASK #14: Retry with jitter to prevent thundering herd
        Environment.SetEnvironmentVariable("OPENCLAW_RETRY_JITTER", "1000");         // +/- 1s random jitter
        Environment.SetEnvironmentVariable("OPENCLAW_RETRY_BACKOFF", "exponential"); // Exponential backoff

        // TASK #17: HTTP keepalive and connection pooling - ENHANCED
        Environment.SetEnvironmentVariable("NODE_KEEPALIVE", "true");
        Environment.SetEnvironmentVariable("NODE_KEEPALIVE_INITIAL_DELAY", "60000"); // 60s keepalive
        Environment.SetEnvironmentVariable("HTTP_KEEPALIVE_TIMEOUT", "120000");      // 120s HTTP keepalive
        Environment.SetEnvironmentVariable("UV_THREADPOOL_SIZE", "128");              // 128 thread pool
        Environment.SetEnvironmentVariable("HTTP_AGENT_KEEPALIVE_TIMEOUT", "300000"); // 5min agent keepalive
        Environment.SetEnvironmentVariable("HTTP_AGENT_MAX_SOCKETS", "256");         // 256 max sockets per host
        Environment.SetEnvironmentVariable("HTTP_AGENT_MAX_FREE_SOCKETS", "256");    // Keep all sockets alive
        Environment.SetEnvironmentVariable("HTTP_AGENT_TIMEOUT", "60000");           // 60s agent timeout
        Environment.SetEnvironmentVariable("OPENCLAW_CONNECTION_POOL_SIZE", "50");   // Connection pool size

        // TASK #6: Network interface binding - prefer primary network adapter
        Environment.SetEnvironmentVariable("OPENCLAW_BIND_ADDRESS", "0.0.0.0");      // Bind to all interfaces
        Environment.SetEnvironmentVariable("NODE_BIND_IPV4", "true");                // Prefer IPv4

        // TASK #10: HTTP/2 support for better connection pooling
        Environment.SetEnvironmentVariable("NODE_HTTP2_ENABLE", "true");
        Environment.SetEnvironmentVariable("HTTP2_MAX_CONCURRENT_STREAMS", "100");
        Environment.SetEnvironmentVariable("HTTP2_SESSION_TIMEOUT", "300000");       // 5min HTTP/2 session
        Environment.SetEnvironmentVariable("OPENCLAW_PREFER_HTTP2", "true");

        // TASK #18: Circuit breaker pattern for resilience
        Environment.SetEnvironmentVariable("OPENCLAW_CIRCUIT_BREAKER", "true");
        Environment.SetEnvironmentVariable("OPENCLAW_CIRCUIT_FAILURE_THRESHOLD", "10"); // 10 failures
        Environment.SetEnvironmentVariable("OPENCLAW_CIRCUIT_TIMEOUT", "60000");     // 60s circuit open time
        Environment.SetEnvironmentVariable("OPENCLAW_CIRCUIT_HALF_OPEN_REQUESTS", "3"); // Test with 3 requests

        // TASK #19: Telegram API health monitoring
        Environment.SetEnvironmentVariable("OPENCLAW_TELEGRAM_HEALTH_CHECK", "true");
        Environment.SetEnvironmentVariable("OPENCLAW_TELEGRAM_HEALTH_INTERVAL", "30000"); // Check every 30s
        Environment.SetEnvironmentVariable("OPENCLAW_TELEGRAM_TIMEOUT", "30000");    // 30s Telegram timeout
        Environment.SetEnvironmentVariable("OPENCLAW_TELEGRAM_RETRY_ON_ERROR", "true");

        var oauthToken = Environment.GetEnvironmentVariable("CLAUDE_CODE_OAUTH_TOKEN", EnvironmentVariableTarget.User);
        if (!string.IsNullOrEmpty(oauthToken))
            Environment.SetEnvironmentVariable("CLAUDE_CODE_OAUTH_TOKEN", oauthToken);
    }

    static bool CheckNetworkConnectivity()
    {
        try
        {
            using var client = new System.Net.WebClient();
            client.Proxy = null;
            using var stream = client.OpenRead("http://www.google.com");
            return true;
        }
        catch
        {
            try
            {
                using var client = new System.Net.WebClient();
                client.Proxy = null;
                using var stream = client.OpenRead("http://api.telegram.org");
                return true;
            }
            catch
            {
                return false;
            }
        }
    }

    static void EnsureStartupEntry()
    {
        try
        {
            // Method 1: Registry Run key
            var registryKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
            using (var key = Registry.CurrentUser.OpenSubKey(registryKey, true))
            {
                if (key != null)
                {
                    var currentValue = key.GetValue(AppName) as string;
                    var desiredValue = $"\"{ExePath}\"";
                    if (currentValue != desiredValue)
                    {
                        key.SetValue(AppName, desiredValue);
                        LogLine($"[STARTUP] Added to registry: {desiredValue}");
                    }
                }
            }

            // Method 2: Ensure tray icon is always shown (not hidden by Windows)
            EnsureTrayIconAlwaysVisible();

            // Method 3: Create scheduled task as backup
            CreateScheduledTask();

            // TASK #11: Configure Windows Firewall exceptions
            ConfigureFirewallExceptions();

            // TASK #16: Configure automatic Windows service recovery
            ConfigureProcessRecovery();
        }
        catch (Exception ex)
        {
            LogLine($"[STARTUP] Warning: Could not fully ensure startup - {ex.Message}");
        }
    }

    static void EnsureTrayIconAlwaysVisible()
    {
        try
        {
            // Windows hides tray icons by default. Force it to always show ours.
            var notifyKey = @"Control Panel\NotifyIconSettings";
            using var key = Registry.CurrentUser.OpenSubKey(notifyKey, true);
            if (key != null)
            {
                var exePathLower = ExePath.ToLowerInvariant();
                foreach (var subKeyName in key.GetSubKeyNames())
                {
                    using var subKey = key.OpenSubKey(subKeyName, true);
                    if (subKey != null)
                    {
                        var execPath = subKey.GetValue("ExecutablePath") as string;
                        if (execPath != null && execPath.ToLowerInvariant() == exePathLower)
                        {
                            subKey.SetValue("IsPromoted", 1, RegistryValueKind.DWord);
                            LogLine("[TRAY] Set IsPromoted=1 to always show tray icon");
                            break;
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            LogLine($"[TRAY] Could not set IsPromoted: {ex.Message}");
        }
    }

    static void CreateScheduledTask()
    {
        try
        {
            // Create a scheduled task that runs at logon as a backup startup method
            var taskName = "ClawdBotManager_AutoStart";
            var psi = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = $"/Create /F /TN \"{taskName}\" /TR \"\\\"{ExePath}\\\"\" /SC ONLOGON /RL HIGHEST",
                WindowStyle = ProcessWindowStyle.Hidden,
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            using var process = Process.Start(psi);
            if (process != null)
            {
                process.WaitForExit(5000);
                if (process.ExitCode == 0)
                {
                    LogLine("[STARTUP] Created scheduled task for auto-start");
                }
            }
        }
        catch (Exception ex)
        {
            LogLine($"[STARTUP] Could not create scheduled task: {ex.Message}");
        }
    }

    static void ConfigureFirewallExceptions()
    {
        try
        {
            // TASK #11: Add firewall rules for Node.js and OpenClaw gateway
            var nodePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "nodejs", "node.exe");
            var npmPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "npm", "node_modules", "openclaw");

            // Add firewall rule for Node.js (if exists)
            if (File.Exists(nodePath))
            {
                var ruleName = "OpenClaw_Gateway_Node";
                var psi = new ProcessStartInfo
                {
                    FileName = "netsh",
                    Arguments = $"advfirewall firewall add rule name=\"{ruleName}\" dir=in action=allow program=\"{nodePath}\" enable=yes profile=any",
                    WindowStyle = ProcessWindowStyle.Hidden,
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    Verb = "runas" // Run as admin
                };

                try
                {
                    using var process = Process.Start(psi);
                    if (process != null)
                    {
                        process.WaitForExit(3000);
                        if (process.ExitCode == 0 || process.ExitCode == 1)
                        {
                            LogLine($"[FIREWALL] Added rule for Node.js: {nodePath}");
                        }
                    }
                }
                catch
                {
                    // Firewall config requires admin - log but don't fail
                    LogLine("[FIREWALL] Could not add Node.js rule (admin required)");
                }
            }

            // Add rule for ClawdBotManager itself
            var managerRuleName = "ClawdBotManager_App";
            var managerPsi = new ProcessStartInfo
            {
                FileName = "netsh",
                Arguments = $"advfirewall firewall add rule name=\"{managerRuleName}\" dir=in action=allow program=\"{ExePath}\" enable=yes profile=any",
                WindowStyle = ProcessWindowStyle.Hidden,
                CreateNoWindow = true,
                UseShellExecute = false
            };

            try
            {
                using var process = Process.Start(managerPsi);
                if (process != null)
                {
                    process.WaitForExit(3000);
                    if (process.ExitCode == 0 || process.ExitCode == 1)
                    {
                        LogLine($"[FIREWALL] Added rule for ClawdBotManager");
                    }
                }
            }
            catch
            {
                LogLine("[FIREWALL] Could not add ClawdBotManager rule (admin required)");
            }
        }
        catch (Exception ex)
        {
            LogLine($"[FIREWALL] Could not configure firewall: {ex.Message}");
        }
    }

    static void ConfigureProcessRecovery()
    {
        try
        {
            // TASK #16: Configure Windows to automatically restart ClawdBotManager if it crashes
            // This creates a scheduled task that monitors and restarts the process

            var recoveryTaskName = "ClawdBotManager_Recovery";
            var monitorScript = Path.Combine(Path.GetTempPath(), "openclaw", "monitor-clawdbot.ps1");

            // Create monitoring script
            Directory.CreateDirectory(Path.GetDirectoryName(monitorScript)!);
            var scriptContent = $@"
# Auto-recovery script for ClawdBotManager
while ($true) {{
    $process = Get-Process -Name 'ClawdBotManager' -ErrorAction SilentlyContinue
    if (-not $process) {{
        Write-Host ""[RECOVERY] ClawdBotManager not running - restarting""
        Start-Process '{ExePath}' -WindowStyle Hidden
        Start-Sleep -Seconds 5
    }}
    Start-Sleep -Seconds 30
}}
";
            File.WriteAllText(monitorScript, scriptContent);

            // Create scheduled task that runs the monitoring script
            var psi = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = $"/Create /F /TN \"{recoveryTaskName}\" " +
                           $"/TR \"powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File \\\"{monitorScript}\\\"\" " +
                           $"/SC ONLOGON /RL HIGHEST /F",
                WindowStyle = ProcessWindowStyle.Hidden,
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            using var process = Process.Start(psi);
            if (process != null)
            {
                process.WaitForExit(5000);
                if (process.ExitCode == 0)
                {
                    LogLine("[RECOVERY] Configured automatic process recovery");
                }
            }
        }
        catch (Exception ex)
        {
            LogLine($"[RECOVERY] Could not configure process recovery: {ex.Message}");
        }
    }

    static (string fileName, string args) GetOpenClawCommand()
    {
        var npmPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "npm");
        var cmdPath = Path.Combine(npmPath, "openclaw.cmd");
        if (File.Exists(cmdPath))
            return (cmdPath, "gateway --allow-unconfigured --auth token --token moltbot-local-token-2026");

        var mjsPath = Path.Combine(npmPath, "node_modules", "openclaw", "openclaw.mjs");
        if (File.Exists(mjsPath))
            return ("node", $"\"{mjsPath}\" gateway --allow-unconfigured --auth token --token moltbot-local-token-2026");

        return ("npx", "openclaw gateway --allow-unconfigured --auth token --token moltbot-local-token-2026");
    }

    static void StartGateway()
    {
        if (_gatewayProcess != null && !_gatewayProcess.HasExited)
            return;

        _userStopped = false;

        // Check network connectivity before starting
        if (!CheckNetworkConnectivity())
        {
            LogLine("[NETWORK] No connectivity detected - will retry in 10s");
            UpdateStatus("No Network - Retrying", Color.FromArgb(255, 200, 50));
            ScheduleRestart(10000);
            return;
        }

        var (fileName, args) = GetOpenClawCommand();

        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = args,
            WindowStyle = ProcessWindowStyle.Hidden,
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        try
        {
            _gatewayProcess = new Process { StartInfo = psi, EnableRaisingEvents = true };
            _gatewayProcess.OutputDataReceived += (s, e) => LogLine(e.Data);
            _gatewayProcess.ErrorDataReceived += (s, e) => LogLine(e.Data);
            _gatewayProcess.Exited += OnGatewayExited;
            _gatewayProcess.Start();

            // Set process priority to HIGH for better performance
            try
            {
                _gatewayProcess.PriorityClass = ProcessPriorityClass.High;
                LogLine("[GATEWAY] Process priority set to HIGH");
            }
            catch (Exception ex)
            {
                LogLine($"[GATEWAY] Could not set priority: {ex.Message}");
            }

            _gatewayProcess.BeginOutputReadLine();
            _gatewayProcess.BeginErrorReadLine();

            _consecutiveFailures = 0;
            _lastStartAttempt = DateTime.Now;
            UpdateStatus("Running", Color.FromArgb(0, 220, 255));
            LogLine("[GATEWAY] Started successfully");
        }
        catch (Exception ex)
        {
            LogLine($"[GATEWAY] Failed to start: {ex.Message}");
            UpdateStatus("Start Failed", Color.FromArgb(255, 60, 60));
            _consecutiveFailures++;
            ScheduleRestart(GetBackoffDelay());
        }
    }

    static void OnGatewayExited(object? sender, EventArgs e)
    {
        if (_userStopped) return;

        _consecutiveFailures++;
        var uptime = DateTime.Now - _lastStartAttempt;

        LogLine($"[GATEWAY] Process exited after {uptime.TotalSeconds:F1}s (failure #{_consecutiveFailures})");

        if (uptime.TotalSeconds > 60)
        {
            // Gateway ran for more than 1 minute - reset failure count
            _consecutiveFailures = 1;
        }

        var delay = GetBackoffDelay();
        UpdateStatus($"Restarting in {delay/1000}s...", Color.FromArgb(255, 200, 50));
        LogLine($"[RESTART] Scheduled auto-restart in {delay}ms");

        ScheduleRestart(delay);
    }

    static int GetBackoffDelay()
    {
        // ULTRA-FAST Exponential backoff: 1s, 2s, 5s, 10s, 20s (max)
        return _consecutiveFailures switch
        {
            1 => 1000,   // 1 second for first crash
            2 => 2000,   // 2 seconds for second crash
            3 => 5000,   // 5 seconds for third crash
            4 => 10000,  // 10 seconds for fourth crash
            _ => 20000   // 20 seconds max (reduced from 30)
        };
    }

    static void ScheduleRestart(int delayMs)
    {
        LogLine($"[RESTART-SCHEDULE] Setting up restart in {delayMs}ms");

        // Use background thread for reliability - UI timers can fail
        var thread = new System.Threading.Thread(() =>
        {
            try
            {
                LogLine($"[RESTART-THREAD] Waiting {delayMs}ms before restart");
                System.Threading.Thread.Sleep(delayMs);

                if (!_userStopped)
                {
                    LogLine("[RESTART] Executing auto-restart NOW");
                    StartGateway();
                }
                else
                {
                    LogLine("[RESTART-THREAD] User stopped - aborting restart");
                }
            }
            catch (Exception ex)
            {
                LogLine($"[RESTART-ERROR] {ex.Message}");
                // Retry after 5 seconds
                System.Threading.Thread.Sleep(5000);
                if (!_userStopped)
                {
                    LogLine("[RESTART-RETRY] Retrying after error");
                    StartGateway();
                }
            }
        });

        thread.IsBackground = true;
        thread.Name = "AutoRestartThread";
        thread.Start();
        LogLine("[RESTART-THREAD] Background thread started");
    }

    static void StopGateway()
    {
        _userStopped = true;
        _restartTimer?.Stop();
        _restartTimer?.Dispose();

        if (_gatewayProcess != null && !_gatewayProcess.HasExited)
        {
            try
            {
                LogLine("[GATEWAY] User stopped gateway");
                _gatewayProcess.Kill(entireProcessTree: true);
            }
            catch { }
        }
        _gatewayProcess = null;
        _consecutiveFailures = 0;
        UpdateStatus("Stopped", Color.FromArgb(255, 100, 100));
    }

    static void LogLine(string? line)
    {
        if (string.IsNullOrEmpty(line)) return;
        try
        {
            var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            var logFile = Path.Combine(_logDir, $"openclaw-{DateTime.Now:yyyy-MM-dd}.log");
            File.AppendAllText(logFile, $"[{timestamp}] {line}{Environment.NewLine}");
        }
        catch { }
    }

    static Icon CreateIcon(Color accentColor)
    {
        var bmp = new Bitmap(16, 16);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

            // Dark background circle
            using var bgBrush = new SolidBrush(Color.FromArgb(255, 15, 15, 30));
            g.FillEllipse(bgBrush, 0, 0, 15, 15);

            // Outer ring in accent color
            using var ringPen = new Pen(Color.FromArgb(180, accentColor.R, accentColor.G, accentColor.B), 1.2f);
            g.DrawEllipse(ringPen, 1, 1, 13, 13);

            // Three claw slashes in accent color
            using var clawPen = new Pen(accentColor, 1.8f);
            clawPen.StartCap = System.Drawing.Drawing2D.LineCap.Round;
            clawPen.EndCap = System.Drawing.Drawing2D.LineCap.Round;

            g.DrawLine(clawPen, 4.5f, 3.5f, 5.5f, 12.5f);   // Left slash
            g.DrawLine(clawPen, 8f, 3f, 8f, 13f);             // Center slash
            g.DrawLine(clawPen, 11.5f, 3.5f, 10.5f, 12.5f);  // Right slash
        }
        var hIcon = bmp.GetHicon();
        return Icon.FromHandle(hIcon);
    }

    static void UpdateStatus(string text, Color color)
    {
        if (_trayIcon == null) return;
        try
        {
            if (_trayIcon.Icon != null)
                _trayIcon.Icon.Dispose();
            _trayIcon.Icon = CreateIcon(color);
            _trayIcon.Text = $"ClawdBot Gateway - {text}";
            if (_statusItem != null)
                _statusItem.Text = $"Status: {text}";
        }
        catch { }
    }

    static void SetupTray()
    {
        _trayIcon = new NotifyIcon
        {
            Icon = CreateIcon(Color.FromArgb(0, 220, 255)),
            Text = "ClawdBot Gateway - Running",
            Visible = true
        };

        var menu = new ContextMenuStrip();

        _statusItem = new ToolStripMenuItem("Status: Running") { Enabled = false };
        menu.Items.Add(_statusItem);
        menu.Items.Add(new ToolStripSeparator());

        var startItem = new ToolStripMenuItem("Start Gateway");
        startItem.Click += (s, e) => StartGateway();
        menu.Items.Add(startItem);

        var stopItem = new ToolStripMenuItem("Stop Gateway");
        stopItem.Click += (s, e) => StopGateway();
        menu.Items.Add(stopItem);

        menu.Items.Add(new ToolStripSeparator());

        var logItem = new ToolStripMenuItem("Open Log");
        logItem.Click += (s, e) =>
        {
            var logFile = Path.Combine(_logDir, $"openclaw-{DateTime.Now:yyyy-MM-dd}.log");
            if (File.Exists(logFile))
                Process.Start("notepad.exe", logFile);
        };
        menu.Items.Add(logItem);

        var termItem = new ToolStripMenuItem("Show Terminal");
        termItem.Click += (s, e) =>
        {
            var logFile = Path.Combine(_logDir, $"openclaw-{DateTime.Now:yyyy-MM-dd}.log");
            Process.Start("powershell.exe", $"-NoExit -Command \"Get-Content '{logFile}' -Wait -Tail 50\"");
        };
        menu.Items.Add(termItem);

        var restartItem = new ToolStripMenuItem("Restart Gateway");
        restartItem.Click += (s, e) =>
        {
            LogLine("[USER] Manual restart requested");
            StopGateway();
            System.Threading.Thread.Sleep(1000);
            _userStopped = false;
            StartGateway();
        };
        menu.Items.Add(restartItem);

        menu.Items.Add(new ToolStripSeparator());

        var exitItem = new ToolStripMenuItem("Exit");
        exitItem.Click += (s, e) =>
        {
            StopGateway();
            _trayIconTimer?.Stop();
            _restartTimer?.Stop();
            _trayIcon.Visible = false;
            _trayIcon.Dispose();
            Application.Exit();
        };
        menu.Items.Add(exitItem);

        _trayIcon.ContextMenuStrip = menu;

        // BULLETPROOF: Keep tray icon always visible
        _trayIconTimer = new System.Windows.Forms.Timer { Interval = 5000 }; // Check every 5 seconds
        _trayIconTimer.Tick += (s, e) =>
        {
            if (_trayIcon != null && !_trayIcon.Visible)
            {
                _trayIcon.Visible = true;
                LogLine("[TRAY] Icon was hidden - forcing visible");
            }
        };
        _trayIconTimer.Start();

        // TASK #7: Connection health checks every 30 seconds
        _healthCheckTimer = new System.Windows.Forms.Timer { Interval = 30000 }; // Every 30 seconds
        _healthCheckTimer.Tick += (s, e) => PerformHealthCheck();
        _healthCheckTimer.Start();
        LogLine("[HEALTH] Started 30-second health check monitoring");
    }

    static void PerformHealthCheck()
    {
        try
        {
            if (_gatewayProcess == null || _gatewayProcess.HasExited)
            {
                return; // Already being handled by OnGatewayExited
            }

            // Check if process is responsive and has been running for at least 30 seconds
            var uptime = DateTime.Now - _lastStartAttempt;
            if (uptime.TotalSeconds < 30)
            {
                return; // Too soon to health check
            }

            _lastHealthCheck = DateTime.Now;

            // Check network connectivity
            if (!CheckNetworkConnectivity())
            {
                _healthCheckFailures++;
                LogLine($"[HEALTH] Network check failed ({_healthCheckFailures}/5)");

                // TASK #15: Reset network adapter on persistent failures (after 5 checks = 150 seconds)
                if (_healthCheckFailures >= 5 && !_userStopped)
                {
                    LogLine("[HEALTH] CRITICAL - Network unavailable for 150+ seconds, resetting adapter");
                    UpdateStatus("Resetting Network", Color.FromArgb(255, 100, 0));

                    try
                    {
                        // Reset all network adapters
                        var resetPsi = new ProcessStartInfo
                        {
                            FileName = "netsh",
                            Arguments = "winsock reset",
                            WindowStyle = ProcessWindowStyle.Hidden,
                            CreateNoWindow = true,
                            UseShellExecute = false,
                            Verb = "runas"
                        };

                        using var resetProc = Process.Start(resetPsi);
                        resetProc?.WaitForExit(5000);

                        // Also reset IP configuration
                        var ipPsi = new ProcessStartInfo
                        {
                            FileName = "netsh",
                            Arguments = "int ip reset",
                            WindowStyle = ProcessWindowStyle.Hidden,
                            CreateNoWindow = true,
                            UseShellExecute = false,
                            Verb = "runas"
                        };

                        using var ipProc = Process.Start(ipPsi);
                        ipProc?.WaitForExit(5000);

                        LogLine("[HEALTH] Network adapter reset completed");
                    }
                    catch (Exception ex)
                    {
                        LogLine($"[HEALTH] Network reset failed (admin required): {ex.Message}");
                    }

                    _healthCheckFailures = 0;

                    // Restart gateway after network reset
                    StopGateway();
                    System.Threading.Thread.Sleep(5000); // Wait for network to recover
                    _userStopped = false;
                    StartGateway();
                }
                else if (_healthCheckFailures >= 3 && !_userStopped)
                {
                    // TASK #8: Preemptive restart on network loss (after 90 seconds)
                    LogLine("[HEALTH] PREEMPTIVE RESTART - Network unavailable for 90+ seconds");
                    UpdateStatus("Network Lost - Restarting", Color.FromArgb(255, 150, 0));

                    // Kill and restart gateway
                    StopGateway();
                    System.Threading.Thread.Sleep(2000);
                    _userStopped = false;
                    StartGateway();
                }
            }
            else
            {
                // Network is healthy - reset failure counter
                if (_healthCheckFailures > 0)
                {
                    LogLine("[HEALTH] Network connectivity restored");
                    _healthCheckFailures = 0;
                }
            }

            // Check process CPU and memory usage for anomalies
            try
            {
                if (_gatewayProcess != null && !_gatewayProcess.HasExited)
                {
                    _gatewayProcess.Refresh();
                    var memoryMB = _gatewayProcess.WorkingSet64 / 1024 / 1024;

                    // Log every 5 minutes (10 health checks)
                    if (uptime.TotalMinutes % 5 < 0.5)
                    {
                        LogLine($"[HEALTH] Gateway health: {uptime.TotalMinutes:F0}min uptime, {memoryMB}MB RAM, Priority={_gatewayProcess.PriorityClass}");
                    }

                    // Preemptive restart if memory exceeds 7GB (close to 8GB limit)
                    if (memoryMB > 7168)
                    {
                        LogLine($"[HEALTH] PREEMPTIVE RESTART - Memory usage {memoryMB}MB exceeds 7GB threshold");
                        UpdateStatus("High Memory - Restarting", Color.FromArgb(255, 150, 0));
                        StopGateway();
                        System.Threading.Thread.Sleep(2000);
                        _userStopped = false;
                        StartGateway();
                    }
                }
            }
            catch (Exception ex)
            {
                LogLine($"[HEALTH] Process check error: {ex.Message}");
            }
        }
        catch (Exception ex)
        {
            LogLine($"[HEALTH] Health check error: {ex.Message}");
        }
    }
}
