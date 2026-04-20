# OpenClaw Auto-Installer

**One-click automated setup for complete OpenClaw environment replication**

This installer packages everything needed to replicate a complete OpenClaw setup on any Windows 11 machine, including:

- ✅ Node.js v24 LTS
- ✅ OpenClaw CLI globally installed
- ✅ System tray integration with auto-start
- ✅ Android Debug Bridge (ADB)
- ✅ Helper scripts (location services, etc.)
- ✅ Pre-configured workspaces and agents
- ✅ Default skills and extensions

## 🚀 Quick Start

### For End Users (Non-Technical)

1. **Download** the installer folder
2. **Double-click** `OpenClawInstaller.cmd`
3. **Follow** the on-screen prompts
4. **Done!** OpenClaw is ready to use

### For Developers (Testing First)

1. **Enable Windows Sandbox** (one-time setup):
   ```powershell
   # Run PowerShell as Administrator
   Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All
   # Restart computer
   ```

2. **Test in Sandbox**:
   ```cmd
   TestInSandbox.cmd
   ```

3. **If test passes, install on main system**:
   ```cmd
   OpenClawInstaller.cmd
   ```

## 📦 What Gets Installed

### Core Components

- **Node.js v24.13.0 LTS**
  - Installed to: `C:\Program Files\nodejs`
  - Added to system PATH automatically

- **OpenClaw CLI**
  - Installed globally via npm
  - Version: Latest stable release
  - Location: `%APPDATA%\npm\node_modules\openclaw`

- **Configuration Directory**
  - Path: `C:\Users\<YourName>\.openclaw`
  - Contains: agents, workspaces, skills, configs

### System Integration

- **System Tray Icon**
  - Auto-starts on boot via startup folder
  - Provides gateway status and controls
  - Right-click menu for restart/logs/stop

- **Auto-Start Configuration**
  - Shortcut in: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`
  - Launches silently on Windows login
  - No console windows

### Additional Tools

- **Android Debug Bridge (ADB)**
  - Location: `C:\Users\<YourName>\.openclaw\platform-tools`
  - Used for Android device integration
  - Version: Latest from Google

- **Helper Scripts**
  - Location: `C:\Users\<YourName>\.openclaw\scripts`
  - Includes: GPS location, screenshot utilities, etc.

## 🔧 Configuration

### API Key Setup

The installer will prompt for your Anthropic API key during installation. If you skip this step, you can set it manually:

```powershell
[System.Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', 'your-api-key-here', 'User')
```

Get your API key at: https://console.anthropic.com/settings/keys

### Telegram Bot (Optional)

To enable Telegram integration:

1. Edit `C:\Users\<YourName>\.openclaw\openclaw.json`
2. Find the `channels.telegram` section
3. Add your bot token:
   ```json
   "telegram": {
     "enabled": true,
     "botToken": "YOUR_BOT_TOKEN_HERE",
     "accounts": { ... }
   }
   ```
4. Restart the gateway (right-click tray icon → Restart)

## 🧪 Testing in Windows Sandbox

Windows Sandbox provides a safe, isolated environment to test the installer without affecting your main system.

### Prerequisites

- Windows 11 Pro, Enterprise, or Education
- Virtualization enabled in BIOS
- At least 4GB RAM available

### Steps

1. **Enable Sandbox** (one-time):
   ```powershell
   # PowerShell as Administrator
   Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All
   Restart-Computer
   ```

2. **Run Test**:
   ```cmd
   TestInSandbox.cmd
   ```

3. **Verify Installation**:
   - Watch the Sandbox window
   - Installer runs automatically
   - Check system tray for OpenClaw icon
   - Test `openclaw status` in PowerShell

4. **Clean Up**:
   - Close the Sandbox window
   - All changes are discarded automatically

## 📋 System Requirements

### Minimum

- Windows 11 (any edition)
- 4GB RAM
- 2GB free disk space
- Internet connection (for downloads)

### Recommended

- Windows 11 Pro/Enterprise (for Sandbox testing)
- 8GB RAM
- 5GB free disk space
- SSD for better performance

## 🛠️ Troubleshooting

### "Script execution is disabled"

Run PowerShell as Administrator and execute:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "Node.js installation failed"

1. Check internet connection
2. Disable antivirus temporarily
3. Run installer as Administrator

### "Gateway won't start"

1. Right-click tray icon → Open Log
2. Check for errors
3. Ensure port 18789 is not blocked
4. Verify ANTHROPIC_API_KEY is set

### "Tray icon not appearing"

1. Check Startup folder for `OpenClawTray.lnk`
2. Run manually: `wscript "C:\Users\<YourName>\.openclaw\tray\OpenClawTray.vbs"`
3. Check Task Manager for running processes

## 📝 Files Included

```
OpenClawAutoInstaller/
├── README.md                    # This file
├── OpenClawInstaller.cmd        # Main installer launcher
├── TestInSandbox.cmd            # Sandbox test launcher
├── setup.ps1                    # Core installation script
├── sandbox-test.wsb             # Sandbox configuration
└── create-installer-exe.ps1     # (Optional) Build standalone EXE
```

## 🔐 Security & Privacy

### What This Installer Does NOT Include

- ❌ API keys or credentials
- ❌ Personal data
- ❌ Private configurations
- ❌ Chat history or logs

### What You Need to Provide

- ✅ Anthropic API key (required)
- ✅ Telegram bot token (optional)
- ✅ Custom workspace files (optional)

### Security Practices

- All downloads are from official sources (nodejs.org, google.com, npmjs.com)
- No executables are bundled - everything is downloaded fresh
- Scripts are plaintext PowerShell - fully auditable
- Sandbox testing available for verification

## 🤝 Support

### Documentation

- OpenClaw Docs: https://docs.openclaw.ai
- GitHub: https://github.com/openclaw/openclaw
- Community: https://discord.com/invite/clawd

### Common Commands

```bash
# Check status
openclaw status

# Start interactive chat
openclaw chat

# Install a skill
openclaw skill add <skill-name>

# View logs
openclaw logs

# Restart gateway
openclaw gateway restart
```

## 📜 License

This installer is provided as-is for OpenClaw setup automation. See OpenClaw project for licensing terms.

---

**Made with ❤️ for the OpenClaw community**

*Last updated: 2026-02-24*
