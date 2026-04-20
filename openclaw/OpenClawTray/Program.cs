using Microsoft.Win32;
using System.Diagnostics;

namespace OpenClawTray;

static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        
        // Add to Windows startup
        AddToStartup();
        
        // Run tray application (no window)
        Application.Run(new TrayApplicationContext());
    }

    private static void AddToStartup()
    {
        try
        {
            string exePath = Application.ExecutablePath;
            using RegistryKey? key = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true);
            if (key != null)
            {
                key.SetValue("OpenClawGateway", exePath);
            }
        }
        catch (Exception ex)
        {
            // Silent fail - don't block app startup
            Debug.WriteLine($"Failed to add to startup: {ex.Message}");
        }
    }
}

internal class TrayApplicationContext : ApplicationContext
{
    private readonly NotifyIcon _trayIcon;
    private Process? _gatewayProcess;

    public TrayApplicationContext()
    {
        // Create tray icon
        _trayIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application, // TODO: Add custom icon
            ContextMenuStrip = new ContextMenuStrip
            {
                Items =
                {
                    new ToolStripMenuItem("OpenClaw Gateway - Running", null, null),
                    new ToolStripSeparator(),
                    new ToolStripMenuItem("Restart", null, (s, e) => RestartGateway()),
                    new ToolStripMenuItem("Exit", null, (s, e) => ExitApplication())
                }
            },
            Visible = true,
            Text = "OpenClaw Gateway"
        };

        // Start gateway process
        StartGateway();
    }

    private void StartGateway()
    {
        try
        {
            _gatewayProcess = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "openclaw",
                    Arguments = "gateway",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = false,
                    RedirectStandardError = false
                }
            };

            _gatewayProcess.EnableRaisingEvents = true;
            _gatewayProcess.Exited += (s, e) =>
            {
                // Gateway crashed - restart it
                System.Threading.Thread.Sleep(2000); // Wait 2 seconds
                StartGateway();
            };

            _gatewayProcess.Start();
            _trayIcon.Text = "OpenClaw Gateway - Running";
        }
        catch (Exception ex)
        {
            _trayIcon.Text = $"OpenClaw Gateway - Error: {ex.Message}";
            MessageBox.Show($"Failed to start OpenClaw Gateway:\n{ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void RestartGateway()
    {
        if (_gatewayProcess != null && !_gatewayProcess.HasExited)
        {
            _gatewayProcess.Kill();
            _gatewayProcess.WaitForExit();
        }
        StartGateway();
    }

    private void ExitApplication()
    {
        _trayIcon.Visible = false;
        
        if (_gatewayProcess != null && !_gatewayProcess.HasExited)
        {
            _gatewayProcess.Kill();
            _gatewayProcess.WaitForExit();
        }

        Application.Exit();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _trayIcon?.Dispose();
            _gatewayProcess?.Dispose();
        }
        base.Dispose(disposing);
    }
}
