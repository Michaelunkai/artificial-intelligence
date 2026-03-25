---
model: anthropic/claude-3-5-haiku-20241022
description: Comprehensive Windows C: drive cleanup from WSL - 70 steps, 30 parallel agents
---

# Windows C: Drive Deep Cleanup from WSL

Execute comprehensive safe cleanup of Windows C: drive accessible at /mnt/c/

## PARALLEL EXECUTION - 30 AGENTS

### AGENT GROUP 1 (Agents 1-6): Windows Temp Files
- TODO 1: Agent 1 - rm -rf /mnt/c/Windows/Temp/* 2>/dev/null
- TODO 2: Agent 2 - rm -rf /mnt/c/Users/*/AppData/Local/Temp/* 2>/dev/null
- TODO 3: Agent 3 - rm -rf /mnt/c/Windows/Prefetch/*.pf 2>/dev/null
- TODO 4: Agent 4 - rm -rf /mnt/c/Windows/SoftwareDistribution/Download/* 2>/dev/null
- TODO 5: Agent 5 - rm -rf /mnt/c/Windows/Logs/CBS/*.log 2>/dev/null
- TODO 6: Agent 6 - rm -rf /mnt/c/Windows/Logs/DISM/*.log 2>/dev/null

### AGENT GROUP 2 (Agents 7-12): Browser Caches
- TODO 7: Agent 7 - rm -rf /mnt/c/Users/*/AppData/Local/Google/Chrome/User\\ Data/Default/Cache/* 2>/dev/null
- TODO 8: Agent 8 - rm -rf /mnt/c/Users/*/AppData/Local/Google/Chrome/User\\ Data/Default/Code\\ Cache/* 2>/dev/null
- TODO 9: Agent 9 - rm -rf /mnt/c/Users/*/AppData/Local/Microsoft/Edge/User\\ Data/Default/Cache/* 2>/dev/null
- TODO 10: Agent 10 - rm -rf /mnt/c/Users/*/AppData/Local/Mozilla/Firefox/Profiles/*/cache2/* 2>/dev/null
- TODO 11: Agent 11 - rm -rf /mnt/c/Users/*/AppData/Local/BraveSoftware/Brave-Browser/User\\ Data/Default/Cache/* 2>/dev/null
- TODO 12: Agent 12 - rm -rf /mnt/c/Users/*/AppData/Local/Opera\\ Software/Opera\\ Stable/Cache/* 2>/dev/null

### AGENT GROUP 3 (Agents 13-18): Application Caches
- TODO 13: Agent 13 - rm -rf /mnt/c/Users/*/AppData/Local/Microsoft/Windows/INetCache/* 2>/dev/null
- TODO 14: Agent 14 - rm -rf /mnt/c/Users/*/AppData/Local/Microsoft/Windows/Explorer/thumbcache_*.db 2>/dev/null
- TODO 15: Agent 15 - rm -rf /mnt/c/Users/*/AppData/Local/IconCache.db 2>/dev/null
- TODO 16: Agent 16 - rm -rf /mnt/c/Users/*/AppData/Local/CrashDumps/* 2>/dev/null
- TODO 17: Agent 17 - rm -rf /mnt/c/Users/*/AppData/Local/Microsoft/Windows/WebCache/* 2>/dev/null
- TODO 18: Agent 18 - rm -rf /mnt/c/Users/*/AppData/Local/Packages/*/TempState/* 2>/dev/null

### AGENT GROUP 4 (Agents 19-24): System Cleanup
- TODO 19: Agent 19 - rm -rf /mnt/c/Windows/System32/LogFiles/WMI/* 2>/dev/null
- TODO 20: Agent 20 - rm -rf /mnt/c/Windows/Panther/*.log 2>/dev/null
- TODO 21: Agent 21 - rm -rf /mnt/c/Windows/INF/*.log 2>/dev/null
- TODO 22: Agent 22 - rm -rf /mnt/c/Windows/System32/winevt/Logs/*.evtx 2>/dev/null (old logs only)
- TODO 23: Agent 23 - rm -rf /mnt/c/Windows/debug/*.log 2>/dev/null
- TODO 24: Agent 24 - rm -rf /mnt/c/Windows/ServiceProfiles/LocalService/AppData/Local/Temp/* 2>/dev/null

### AGENT GROUP 5 (Agents 25-30): Downloads & Recycle
- TODO 25: Agent 25 - find /mnt/c/Users/*/Downloads -type f -mtime +30 -name "*.exe" -delete 2>/dev/null
- TODO 26: Agent 26 - find /mnt/c/Users/*/Downloads -type f -mtime +30 -name "*.msi" -delete 2>/dev/null
- TODO 27: Agent 27 - find /mnt/c/Users/*/Downloads -type f -mtime +60 -name "*.zip" -delete 2>/dev/null
- TODO 28: Agent 28 - find /mnt/c/Users/*/Downloads -type f -mtime +60 -name "*.rar" -delete 2>/dev/null
- TODO 29: Agent 29 - rm -rf '/mnt/c/$Recycle.Bin'/*/* 2>/dev/null
- TODO 30: Agent 30 - rm -rf /mnt/c/Users/*/AppData/Local/D3DSCache/* 2>/dev/null

## SEQUENTIAL EXECUTION - REMAINING 40 TASKS

### Windows Update Cleanup
- TODO 31: rm -rf /mnt/c/Windows/SoftwareDistribution/DataStore/Logs/* 2>/dev/null
- TODO 32: rm -rf /mnt/c/Windows/WinSxS/Backup/* 2>/dev/null
- TODO 33: find /mnt/c/Windows/Installer -name "*.tmp" -delete 2>/dev/null
- TODO 34: rm -rf /mnt/c/Windows/Logs/WindowsUpdate/*.etl 2>/dev/null
- TODO 35: rm -rf /mnt/c/ProgramData/Microsoft/Windows/WER/ReportArchive/* 2>/dev/null
- TODO 36: rm -rf /mnt/c/ProgramData/Microsoft/Windows/WER/ReportQueue/* 2>/dev/null

### User Profile Cleanup
- TODO 37: rm -rf /mnt/c/Users/*/AppData/Local/Microsoft/Windows/Caches/* 2>/dev/null
- TODO 38: rm -rf /mnt/c/Users/*/AppData/Local/Microsoft/CLR_v4.0/UsageLogs/* 2>/dev/null
- TODO 39: rm -rf /mnt/c/Users/*/AppData/Local/Microsoft/CLR_v2.0/UsageLogs/* 2>/dev/null
- TODO 40: rm -rf /mnt/c/Users/*/AppData/Local/Microsoft/Windows/History/* 2>/dev/null
- TODO 41: rm -rf /mnt/c/Users/*/AppData/Local/Microsoft/Terminal\\ Server\\ Client/Cache/* 2>/dev/null
- TODO 42: rm -rf /mnt/c/Users/*/AppData/Roaming/Microsoft/Windows/Recent/* 2>/dev/null

### Developer Tool Caches
- TODO 43: rm -rf /mnt/c/Users/*/.nuget/packages/*/content/* 2>/dev/null
- TODO 44: rm -rf /mnt/c/Users/*/AppData/Roaming/npm-cache/* 2>/dev/null
- TODO 45: rm -rf /mnt/c/Users/*/AppData/Local/pip/cache/* 2>/dev/null
- TODO 46: rm -rf /mnt/c/Users/*/.gradle/caches/* 2>/dev/null
- TODO 47: rm -rf /mnt/c/Users/*/.m2/repository/*/.cache 2>/dev/null
- TODO 48: rm -rf /mnt/c/Users/*/AppData/Local/Yarn/Cache/* 2>/dev/null

### Visual Studio & IDE Cleanup
- TODO 49: rm -rf /mnt/c/Users/*/AppData/Local/Microsoft/VisualStudio/*/ComponentModelCache/* 2>/dev/null
- TODO 50: rm -rf /mnt/c/Users/*/AppData/Roaming/Code/Cache/* 2>/dev/null
- TODO 51: rm -rf /mnt/c/Users/*/AppData/Roaming/Code/CachedData/* 2>/dev/null
- TODO 52: rm -rf /mnt/c/Users/*/AppData/Roaming/Code/CachedExtensions/* 2>/dev/null
- TODO 53: rm -rf /mnt/c/Users/*/AppData/Roaming/Code/CachedExtensionVSIXs/* 2>/dev/null
- TODO 54: rm -rf /mnt/c/Users/*/AppData/Local/JetBrains/*/caches/* 2>/dev/null

### Gaming & Media Caches
- TODO 55: rm -rf /mnt/c/Users/*/AppData/Local/Steam/htmlcache/* 2>/dev/null
- TODO 56: rm -rf /mnt/c/Users/*/AppData/Local/Discord/Cache/* 2>/dev/null
- TODO 57: rm -rf /mnt/c/Users/*/AppData/Local/Discord/Code\\ Cache/* 2>/dev/null
- TODO 58: rm -rf /mnt/c/Users/*/AppData/Local/Spotify/Storage/* 2>/dev/null
- TODO 59: rm -rf /mnt/c/Users/*/AppData/Roaming/Slack/Cache/* 2>/dev/null
- TODO 60: rm -rf /mnt/c/Users/*/AppData/Local/Microsoft/Teams/Cache/* 2>/dev/null

### Old & Backup File Cleanup
- TODO 61: find /mnt/c/Users -name "*.bak" -mtime +90 -delete 2>/dev/null
- TODO 62: find /mnt/c/Users -name "*.old" -mtime +90 -delete 2>/dev/null
- TODO 63: find /mnt/c/Users -name "*.tmp" -mtime +7 -delete 2>/dev/null
- TODO 64: find /mnt/c/Users -name "~*" -mtime +30 -delete 2>/dev/null
- TODO 65: find /mnt/c/Users -name "Thumbs.db" -delete 2>/dev/null
- TODO 66: find /mnt/c/Users -name "desktop.ini" -mtime +365 -delete 2>/dev/null

### Final System Cleanup
- TODO 67: rm -rf /mnt/c/Windows/Memory.dmp 2>/dev/null
- TODO 68: rm -rf /mnt/c/Windows/Minidump/* 2>/dev/null
- TODO 69: rm -rf /mnt/c/Windows/LiveKernelReports/* 2>/dev/null
- TODO 70: du -sh /mnt/c/ && echo "Cleanup complete! Run 'df -h /mnt/c' for space summary"

Report total space freed after all operations complete.
