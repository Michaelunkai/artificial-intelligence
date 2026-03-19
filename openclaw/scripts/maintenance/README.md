# OpenClaw Mega Fix Scripts

## 📁 Files

### 1. `openclaw-megafix.ps1` (Original)
- **43 commands** - Native OpenClaw CLI diagnostics only
- Basic health checks, repairs, and service restarts
- Safe for all users

### 2. `openclaw-megafix-enhanced.ps1` (RECOMMENDED)
- **80+ commands** - Comprehensive diagnostics including third-party tools
- Organized into 5 sections:
  1. Native OpenClaw diagnostics (43 commands)
  2. NPM & Node.js diagnostics (12 commands)
  3. System diagnostics (15 commands)
  4. File integrity & permissions (5 commands)
  5. Final repairs & restarts (5 commands)

### 3. `openclaw-megafix-oneliner.txt`
- Single-line command chain for quick execution
- All commands from original script in one line

---

## 🚀 Usage

### Run Enhanced Script (Recommended)
```powershell
powershell -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\openclaw\scripts\maintenance\openclaw-megafix-enhanced.ps1"
```

### Run Original Script
```powershell
powershell -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\openclaw\scripts\maintenance\openclaw-megafix.ps1"
```

### Run One-Liner
Copy contents of `openclaw-megafix-oneliner.txt` and paste into PowerShell.

---

## 📊 What Gets Checked/Fixed

### Native OpenClaw Diagnostics
- ✅ Config validation
- ✅ Security audits with auto-fix
- ✅ Gateway health, status, and reachability
- ✅ Channels (Telegram, Discord, etc.) status
- ✅ Browser automation service
- ✅ Sandbox containers
- ✅ Memory indexing
- ✅ Plugins and skills
- ✅ Models configuration
- ✅ Cron jobs, hooks, approvals
- ✅ Backup creation
- ✅ Service restarts (gateway + browser)

### NPM & Node.js Diagnostics (Enhanced Only)
- ✅ Node.js and npm version checks
- ✅ Global package health
- ✅ npm cache verification
- ✅ npm doctor diagnostics
- ✅ OpenClaw update availability
- ✅ Plugin discovery on npm registry
- ✅ node_modules integrity
- ✅ Outdated package detection

### System Diagnostics (Enhanced Only)
- ✅ Process monitoring (OpenClaw, Node, Chrome)
- ✅ Port conflict detection (18790, 18792)
- ✅ Docker status (for sandbox)
- ✅ Environment variables validation
- ✅ Disk space checks
- ✅ Log file analysis
- ✅ Network connectivity tests
- ✅ DNS resolution
- ✅ System uptime
- ✅ Windows/PowerShell version

### File Integrity & Permissions (Enhanced Only)
- ✅ Config file permissions
- ✅ Workspace permissions
- ✅ Binary verification
- ✅ Corrupted file detection
- ✅ Skills directory validation

---

## 🛡️ Safety

**All scripts are non-destructive:**
- ❌ No user data deleted
- ❌ No configs removed
- ❌ No credentials cleared
- ✅ Only applies safe repairs with `--fix` flags
- ✅ Creates backups before repairs
- ✅ Restarts services cleanly

---

## 🔧 Common Issues Fixed

### 1. Browser Timeout Errors
**Symptoms:** `Can't reach the OpenClaw browser control service (timed out after Nms)`

**Fixed by:**
- Command #12-14: Browser status + start
- Command #39/77: Browser cycle (stop + restart)
- Command #57-58: Port conflict detection

### 2. File Not Found Errors
**Symptoms:** `ENOENT: no such file or directory`

**Fixed by:**
- Command #71-75: File integrity checks
- Command #62: Config directory validation
- Command #64: Workspace verification

### 3. Gateway Connection Issues
**Fixed by:**
- Command #6-8: Gateway status, health, probe
- Command #38/76: Gateway restart
- Command #56: Process monitoring
- Command #60: Environment variables

### 4. Plugin/Skill Loading Failures
**Fixed by:**
- Command #20-21: Plugin diagnostics
- Command #22-23: Skills checks
- Command #75: Skills directory validation

### 5. Memory/Performance Issues
**Fixed by:**
- Command #17-19: Memory reindexing
- Command #48: npm cache verification
- Command #61: Disk space monitoring
- Command #65: Browser process memory check

---

## 📝 Output Logging

Enhanced script automatically saves logs to:
```
~\.openclaw\logs\megafix-YYYYMMDD-HHmmss.log
```

Review this log after running for detailed diagnostics.

---

## 🔄 When to Run

### Daily/Regular Use
Use **original script** (`openclaw-megafix.ps1`):
- Quick 43-command health check
- ~2-3 minutes runtime
- Safe for automation

### Deep Troubleshooting
Use **enhanced script** (`openclaw-megafix-enhanced.ps1`):
- Comprehensive 80+ command diagnostics
- ~5-10 minutes runtime
- Run when experiencing issues
- Run after major updates
- Run weekly for maintenance

### Emergency Quick Fix
Use **one-liner** (`openclaw-megafix-oneliner.txt`):
- Single command execution
- No script file needed
- Copy-paste into PowerShell

---

## 🆘 If Issues Persist

After running megafix, if problems continue:

1. **Check the logs:**
   ```powershell
   openclaw logs --lines 100
   ```

2. **Run doctor manually with verbose output:**
   ```powershell
   openclaw doctor --deep --verbose
   ```

3. **Check specific failing component:**
   ```powershell
   # For browser issues:
   openclaw browser status
   
   # For gateway issues:
   openclaw gateway health
   
   # For channel issues:
   openclaw channels status --deep
   ```

4. **Consult OpenClaw docs:**
   ```
   https://docs.openclaw.ai
   ```

5. **Join community Discord:**
   ```
   https://discord.com/invite/clawd
   ```

---

## 🔗 Related Resources

- **OpenClaw Docs:** https://docs.openclaw.ai
- **OpenClaw GitHub:** https://github.com/openclaw/openclaw
- **Community Skills:** https://clawhub.com
- **NPM Package:** https://www.npmjs.com/package/openclaw

---

## 📜 Version History

- **2026-03-12:** Enhanced script created (80+ commands)
- **2026-03-12:** Original script created (43 commands)
- **2026-03-12:** One-liner version added

---

## 📄 License

These scripts are provided as-is for OpenClaw maintenance.
Safe for personal and commercial use.
