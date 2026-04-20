namespace OpenClawRunner;

static class Program
{
    /// <summary>
    ///  The main entry point for the application.
    /// </summary>
    [STAThread]
    static void Main()
    {
        // Prevent multiple instances
        using Mutex mutex = new Mutex(true, "OpenClawRunner_SingleInstance", out bool createdNew);
        if (!createdNew)
        {
            // Another instance is already running
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new Form1());
    }    
}