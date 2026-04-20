using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace TgTray
{
    // =====================================================================
    //  tg.exe — Claude Telegram Channel Manager
    //
    //  tg              → show status; if tray not running, launch it
    //  tg status       → print status to console, exit
    //  tg start        → start channel, exit
    //  tg stop         → stop channel, exit
    //  tg restart      → clean restart, exit
    //  tg tray         → force-launch system tray (even if already running)
    //  tg tui          → open live TUI terminal
    // =====================================================================

    static class Program
    {
        [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")]   static extern bool ShowWindow(IntPtr hWnd, int nCmd);
        const int SW_HIDE = 0;
        const int SW_MINIMIZE = 6;

        public static readonly string ChannelDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claude", "channels");
        static readonly string Ps5 = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell", "v1.0", "powershell.exe");

        [STAThread]
        static void Main(string[] args)
        {
            try { _Main(args); }
            catch (Exception ex)
            {
                try { File.WriteAllText(@"C:\temp\tg-crash.txt", ex.ToString()); } catch {}
                Console.Error.WriteLine("CRASH: " + ex.Message);
                Console.Error.WriteLine(ex.StackTrace);
            }
        }

        static void _Main(string[] args)
        {
            string cmd = args.Length > 0 ? args[0].ToLower() : "";

            switch (cmd)
            {
                case "status":
                    PrintStatus();
                    return;

                case "start":
                    var st = GetState();
                    if (st.IsRunning)
                    {
                        Console.WriteLine("Channel already RUNNING (Runner PID " + st.RunnerPid + ", Claude PID " + st.ClaudePid + ")");
                    }
                    else
                    {
                        RunPs("-File \"" + Path.Combine(ChannelDir, "launch-channel.ps1") + "\"", hidden: true);
                        Console.WriteLine("Channel starting... allow 15-20s. Run 'tg status' to check.");
                    }
                    return;

                case "stop":
                    StopChannel();
                    Console.WriteLine("Channel stopped.");
                    return;

                case "restart":
                    RestartChannel();
                    Console.WriteLine("Channel restarting (clean)... allow ~30s.");
                    return;

                case "tray":
                    LaunchTray(mustBeNew: false);
                    return;

                case "tui":
                    OpenTui();
                    return;

                default:
                    // No args: show status + ensure tray is running
                    PrintStatus();
                    Console.WriteLine("");
                    LaunchTray(mustBeNew: false);
                    return;
            }
        }

        // ─── Tray launcher ────────────────────────────────────────────────────
        static void LaunchTray(bool mustBeNew)
        {
            bool created;
            var mutex = new Mutex(true, "TgTrayApp_Claude_2025", out created);

            if (!created)
            {
                if (mustBeNew)
                    Console.WriteLine("System tray already running.");
                else
                    Console.WriteLine("System tray: already in tray. Right-click the TG icon in your taskbar.");
                mutex.Dispose();
                return;
            }

            // Hide console window immediately (minimize then hide to reduce flicker)
            IntPtr con = GetConsoleWindow();
            ShowWindow(con, SW_MINIMIZE);
            ShowWindow(con, SW_HIDE);

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new TrayApp(mutex));
            mutex.Dispose();
        }

        // ─── TUI launcher ─────────────────────────────────────────────────────
        public static void OpenTui()
        {
            string tuiScript = Path.Combine(ChannelDir, "tui.ps1");
            if (!File.Exists(tuiScript))
            {
                Console.WriteLine("TUI script not found: " + tuiScript);
                return;
            }
            var psi = new ProcessStartInfo
            {
                FileName         = Ps5,
                Arguments        = "-NoProfile -ExecutionPolicy Bypass -File \"" + tuiScript + "\"",
                WindowStyle      = ProcessWindowStyle.Normal,
                CreateNoWindow   = false,
                UseShellExecute  = true,
            };
            Process.Start(psi);
        }

        // ─── Channel process detection ─────────────────────────────────────────
        public struct State
        {
            public bool HasRunner, HasClaude;
            public int BunCount, RunnerPid, ClaudePid;
            public bool IsRunning { get { return HasRunner && HasClaude; } }
        }

        public static State GetState()
        {
            var s = new State();
            try
            {
                var q = new ManagementObjectSearcher(
                    "SELECT ProcessId, Name, CommandLine FROM Win32_Process " +
                    "WHERE Name='powershell.exe' OR Name='claude.exe' OR Name='bun.exe'");
                foreach (ManagementObject o in q.Get())
                {
                    string name = (o["Name"] ?? "").ToString();
                    string cmd  = (o["CommandLine"] ?? "").ToString();
                    int    pid  = Convert.ToInt32(o["ProcessId"]);

                    if (name == "powershell.exe" && cmd.Contains("run-channel.ps1"))
                    { s.HasRunner = true;  s.RunnerPid = pid; }
                    else if (name == "claude.exe" && cmd.Contains("--channels"))
                    { s.HasClaude = true; s.ClaudePid = pid; }
                    else if (name == "bun.exe")
                    { s.BunCount++; }
                }
            }
            catch { }
            return s;
        }

        // ─── Console status print ──────────────────────────────────────────────
        static void PrintStatus()
        {
            var s = GetState();
            Console.WriteLine("=== Claude Telegram Channel ===");
            Console.WriteLine("Status:  " + (s.IsRunning ? "RUNNING" : "STOPPED"));
            if (s.IsRunning)
            {
                Console.WriteLine("Runner:  PID " + s.RunnerPid);
                Console.WriteLine("Claude:  PID " + s.ClaudePid);
                Console.WriteLine("Bun:     " + s.BunCount + " process(es)");
            }
            Console.WriteLine("Bot:     @michaelovsky5c3344545laud5e5_bot");

            // Last 3 debug log lines
            string logPath = Path.Combine(ChannelDir, "tg-debug.log");
            if (File.Exists(logPath))
            {
                try
                {
                    string[] lines = File.ReadAllLines(logPath);
                    int start = Math.Max(0, lines.Length - 3);
                    Console.WriteLine("--- last activity ---");
                    for (int i = start; i < lines.Length; i++)
                        Console.WriteLine(lines[i]);
                }
                catch { }
            }
        }

        // ─── Channel control ───────────────────────────────────────────────────
        public static void StartChannel()
        {
            RunPs("-File \"" + Path.Combine(ChannelDir, "launch-channel.ps1") + "\"", hidden: true);
        }

        public static void StopChannel()
        {
            string script =
                "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'bun.exe' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; " +
                "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'claude.exe' -and $_.CommandLine -like '*--channels*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; " +
                "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*run-channel.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }";
            RunPs("-Command \"" + script + "\"", hidden: true);
        }

        public static void RestartChannel()
        {
            RunPs("-File \"" + Path.Combine(ChannelDir, "clean-restart.ps1") + "\"", hidden: true);
        }

        public static void RunPs(string psArgs, bool hidden)
        {
            var psi = new ProcessStartInfo
            {
                FileName        = Ps5,
                Arguments       = "-NoProfile -ExecutionPolicy Bypass " + psArgs,
                WindowStyle     = hidden ? ProcessWindowStyle.Hidden : ProcessWindowStyle.Normal,
                CreateNoWindow  = hidden,
                UseShellExecute = true,
            };
            Process.Start(psi);
        }
    }

    // =========================================================================
    //  System Tray Application
    // =========================================================================
    class TrayApp : ApplicationContext
    {
        private readonly NotifyIcon trayIcon;
        private readonly System.Windows.Forms.Timer timer;
        private readonly Mutex ownerMutex;
        private bool wasRunning = false;

        private ToolStripMenuItem headerItem, startItem, stopItem, restartItem;

        public TrayApp(Mutex mutex)
        {
            ownerMutex = mutex;

            var menu = new ContextMenuStrip();

            headerItem = new ToolStripMenuItem("Claude Telegram");
            headerItem.Enabled = false;
            headerItem.Font = new Font(headerItem.Font.FontFamily, headerItem.Font.Size, FontStyle.Bold);
            menu.Items.Add(headerItem);
            menu.Items.Add(new ToolStripSeparator());

            startItem   = new ToolStripMenuItem("▶  Start Channel",   null, OnStart);
            stopItem    = new ToolStripMenuItem("■  Stop Channel",    null, OnStop);
            restartItem = new ToolStripMenuItem("↺  Restart Channel", null, OnRestart);
            var tuiItem      = new ToolStripMenuItem("📺  TUI — Live Terminal",  null, OnTui);
            var logDebugItem = new ToolStripMenuItem("📋  Debug Log",            null, OnDebugLog);
            var logChanItem  = new ToolStripMenuItem("📄  Channel Log",          null, OnChannelLog);
            var exitItem     = new ToolStripMenuItem("✖  Exit Tray",             null, OnExit);

            menu.Items.Add(startItem);
            menu.Items.Add(stopItem);
            menu.Items.Add(restartItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(tuiItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(logDebugItem);
            menu.Items.Add(logChanItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(exitItem);

            trayIcon = new NotifyIcon
            {
                ContextMenuStrip = menu,
                Visible          = true,
                Icon             = MakeIcon(false),
                Text             = "Claude Telegram Channel"
            };
            trayIcon.DoubleClick += OnTui;

            timer = new System.Windows.Forms.Timer { Interval = 5000 };
            timer.Tick += OnTick;
            timer.Start();

            Tick(); // immediate first update
        }

        // ─── Icon ─────────────────────────────────────────────────────────────
        static Icon MakeIcon(bool running)
        {
            var bmp = new Bitmap(32, 32, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);

                Color bg = running ? Color.FromArgb(39, 174, 96) : Color.FromArgb(192, 57, 43);
                using (var b = new SolidBrush(bg))
                    g.FillEllipse(b, 1, 1, 29, 29);
                using (var p = new Pen(Color.FromArgb(210, 210, 210), 1.5f))
                    g.DrawEllipse(p, 1, 1, 29, 29);

                var sf = new StringFormat
                {
                    Alignment     = StringAlignment.Center,
                    LineAlignment = StringAlignment.Center
                };
                using (var f  = new Font("Arial", 10.5f, FontStyle.Bold))
                using (var tb = new SolidBrush(Color.White))
                    g.DrawString("TG", f, tb, new RectangleF(1, 1, 29, 29), sf);
            }
            return Icon.FromHandle(bmp.GetHicon());
        }

        // ─── Polling ──────────────────────────────────────────────────────────
        void OnTick(object sender, EventArgs e) { Tick(); }

        void Tick()
        {
            var s = Program.GetState();

            trayIcon.Icon = MakeIcon(s.IsRunning);
            headerItem.Text = "Claude Telegram  " + (s.IsRunning ? "●" : "○");
            trayIcon.Text   = s.IsRunning
                ? "Claude Telegram: RUNNING\n@michaelovsky5c3344545laud5e5_bot"
                : "Claude Telegram: STOPPED";

            startItem.Enabled   = !s.IsRunning;
            stopItem.Enabled    =  s.IsRunning;
            restartItem.Enabled =  true;

            if (s.IsRunning && !wasRunning)
                Balloon("Channel ONLINE", "Claude Telegram channel is now connected.", ToolTipIcon.Info);
            else if (!s.IsRunning && wasRunning)
                Balloon("Channel OFFLINE", "Claude Telegram channel went offline.", ToolTipIcon.Warning);

            wasRunning = s.IsRunning;
        }

        void Balloon(string title, string text, ToolTipIcon icon)
        {
            trayIcon.BalloonTipTitle = title;
            trayIcon.BalloonTipText  = text;
            trayIcon.BalloonTipIcon  = icon;
            trayIcon.ShowBalloonTip(4000);
        }

        // ─── Menu handlers ────────────────────────────────────────────────────
        void OnStart(object sender, EventArgs e)
        {
            Program.StartChannel();
            Balloon("Starting", "Channel starting up... allow 15-20s.", ToolTipIcon.Info);
        }

        void OnStop(object sender, EventArgs e)
        {
            Program.StopChannel();
            Balloon("Stopping", "Sending stop signal...", ToolTipIcon.Info);
        }

        void OnRestart(object sender, EventArgs e)
        {
            Program.RestartChannel();
            Balloon("Restarting", "Clean restart initiated... allow ~30s.", ToolTipIcon.Info);
        }

        void OnTui(object sender, EventArgs e)
        {
            Program.OpenTui();
        }

        void OnDebugLog(object sender, EventArgs e)
        {
            OpenFile(Path.Combine(Program.ChannelDir, "tg-debug.log"));
        }

        void OnChannelLog(object sender, EventArgs e)
        {
            OpenFile(Path.Combine(Program.ChannelDir, "channel.log"));
        }

        static void OpenFile(string path)
        {
            if (File.Exists(path))
                Process.Start("notepad.exe", path);
            // File not found: silently ignore — no popup
        }

        void OnExit(object sender, EventArgs e)
        {
            trayIcon.Visible = false;
            Application.Exit();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (timer != null) timer.Dispose();
                if (trayIcon != null) trayIcon.Dispose();
                if (ownerMutex != null) ownerMutex.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
