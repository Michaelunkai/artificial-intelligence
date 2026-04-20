using System.Diagnostics;
using Microsoft.Win32;

namespace OpenClawRunner
{
    public partial class Form1 : Form
    {
        private NotifyIcon? trayIcon;
        private Process? openclawProcess;
        private System.Windows.Forms.Timer? watchdogTimer;
        private const string APP_NAME = "OpenClawRunner";

        public Form1()
        {
            InitializeComponent();
            InitializeTrayIcon();
            AddToStartup();
            StartOpenClaw();
            StartWatchdog();

            // Hide the form immediately - we only want tray icon
            this.WindowState = FormWindowState.Minimized;
            this.ShowInTaskbar = false;
            this.Visible = false;
        }

        private void InitializeTrayIcon()
        {
            trayIcon = new NotifyIcon
            {
                Text = "OpenClaw Gateway",
                Visible = true,
                ContextMenuStrip = new ContextMenuStrip()
            };

            // Create a simple icon (green circle when running)
            using (Bitmap bmp = new Bitmap(16, 16))
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);
                g.FillEllipse(Brushes.LimeGreen, 2, 2, 12, 12);
                trayIcon.Icon = Icon.FromHandle(bmp.GetHicon());
            }

            // Add menu items
            var exitItem = new ToolStripMenuItem("Exit");
            exitItem.Click += (s, e) =>
            {
                watchdogTimer?.Stop();
                watchdogTimer?.Dispose();
                StopOpenClaw();
                Application.Exit();
            };

            var restartItem = new ToolStripMenuItem("Restart Gateway");
            restartItem.Click += (s, e) =>
            {
                StopOpenClaw();
                Task.Delay(1000).ContinueWith(_ => StartOpenClaw());
            };

            trayIcon.ContextMenuStrip.Items.Add(restartItem);
            trayIcon.ContextMenuStrip.Items.Add(new ToolStripSeparator());
            trayIcon.ContextMenuStrip.Items.Add(exitItem);
        }

        private void AddToStartup()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)!)
                {
                    string exePath = Application.ExecutablePath;
                    key.SetValue(APP_NAME, exePath);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Could not add to startup: {ex.Message}", "Warning");
            }
        }

        private void StartWatchdog()
        {
            watchdogTimer = new System.Windows.Forms.Timer
            {
                Interval = 10000 // Check every 10 seconds
            };
            watchdogTimer.Tick += (s, e) =>
            {
                if (openclawProcess == null || openclawProcess.HasExited)
                {
                    StartOpenClaw();
                }
            };
            watchdogTimer.Start();
        }

        private void StartOpenClaw()
        {
            try
            {
                // Kill any existing process first
                if (openclawProcess != null && !openclawProcess.HasExited)
                {
                    return; // Already running
                }

                openclawProcess = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = "powershell.exe",
                        Arguments = "-NoProfile -WindowStyle Hidden -Command \"openclaw gateway\"",
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        WindowStyle = ProcessWindowStyle.Hidden
                    }
                };

                openclawProcess.Start();
            }
            catch (Exception ex)
            {
                // Silently retry on next watchdog tick
            }
        }

        private void StopOpenClaw()
        {
            try
            {
                if (openclawProcess != null && !openclawProcess.HasExited)
                {
                    openclawProcess.Kill(true);
                    openclawProcess.WaitForExit(5000);
                    openclawProcess.Dispose();
                }
            }
            catch { }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                this.Hide();
            }
            else
            {
                watchdogTimer?.Stop();
                watchdogTimer?.Dispose();
                StopOpenClaw();
                trayIcon?.Dispose();
            }
            base.OnFormClosing(e);
        }
    }
}
