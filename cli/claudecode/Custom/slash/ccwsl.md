---
model: anthropic/claude-3-5-haiku-20241022
description: Comprehensive WSL Ubuntu cleanup including wslg - 70 steps, 30 parallel agents
---

# WSL Ubuntu Deep Cleanup

Execute comprehensive safe cleanup of WSL Ubuntu filesystem including /mnt/wslg

## PARALLEL EXECUTION - 30 AGENTS

### AGENT GROUP 1 (Agents 1-6): APT Package Cleanup
- TODO 1: Agent 1 - sudo apt-get clean -y
- TODO 2: Agent 2 - sudo apt-get autoclean -y
- TODO 3: Agent 3 - sudo apt-get autoremove --purge -y
- TODO 4: Agent 4 - sudo rm -rf /var/cache/apt/archives/*.deb
- TODO 5: Agent 5 - sudo rm -rf /var/cache/apt/archives/partial/*
- TODO 6: Agent 6 - sudo rm -rf /var/lib/apt/lists/*

### AGENT GROUP 2 (Agents 7-12): System Logs
- TODO 7: Agent 7 - sudo journalctl --vacuum-time=3d
- TODO 8: Agent 8 - sudo rm -rf /var/log/*.gz
- TODO 9: Agent 9 - sudo rm -rf /var/log/*.1
- TODO 10: Agent 10 - sudo rm -rf /var/log/**/*.gz
- TODO 11: Agent 11 - sudo truncate -s 0 /var/log/syslog
- TODO 12: Agent 12 - sudo truncate -s 0 /var/log/kern.log

### AGENT GROUP 3 (Agents 13-18): User Cache Cleanup
- TODO 13: Agent 13 - rm -rf ~/.cache/*
- TODO 14: Agent 14 - rm -rf ~/.local/share/Trash/*
- TODO 15: Agent 15 - rm -rf ~/.thumbnails/*
- TODO 16: Agent 16 - rm -rf ~/.local/share/recently-used.xbel
- TODO 17: Agent 17 - rm -rf ~/.xsession-errors*
- TODO 18: Agent 18 - rm -rf ~/.bash_history && touch ~/.bash_history

### AGENT GROUP 4 (Agents 19-24): Developer Tool Cleanup
- TODO 19: Agent 19 - rm -rf ~/.npm/_cacache/*
- TODO 20: Agent 20 - rm -rf ~/.npm/_logs/*
- TODO 21: Agent 21 - rm -rf ~/.cache/pip/*
- TODO 22: Agent 22 - rm -rf ~/.cargo/registry/cache/*
- TODO 23: Agent 23 - rm -rf ~/.rustup/tmp/*
- TODO 24: Agent 24 - rm -rf ~/.cache/go-build/*

### AGENT GROUP 5 (Agents 25-30): WSLg & Temp Cleanup
- TODO 25: Agent 25 - rm -rf /mnt/wslg/distro/usr/share/doc/*
- TODO 26: Agent 26 - rm -rf /mnt/wslg/distro/usr/share/man/*
- TODO 27: Agent 27 - rm -rf /mnt/wslg/distro/var/cache/*
- TODO 28: Agent 28 - rm -rf /tmp/*
- TODO 29: Agent 29 - rm -rf /var/tmp/*
- TODO 30: Agent 30 - sudo rm -rf /var/crash/*

## SEQUENTIAL EXECUTION - REMAINING 40 TASKS

### More Log Cleanup
- TODO 31: sudo rm -rf /var/log/journal/*
- TODO 32: sudo truncate -s 0 /var/log/auth.log
- TODO 33: sudo truncate -s 0 /var/log/dpkg.log
- TODO 34: sudo truncate -s 0 /var/log/alternatives.log
- TODO 35: sudo truncate -s 0 /var/log/bootstrap.log
- TODO 36: sudo rm -rf /var/log/installer/*

### Snap Cleanup (if installed)
- TODO 37: snap list --all | awk '/disabled/{print $1, $3}' | while read pkg rev; do sudo snap remove "$pkg" --revision="$rev"; done 2>/dev/null || true
- TODO 38: rm -rf ~/snap/*/.cache/* 2>/dev/null || true
- TODO 39: sudo rm -rf /var/lib/snapd/cache/* 2>/dev/null || true
- TODO 40: sudo rm -rf /var/lib/snapd/snaps/*.snap~ 2>/dev/null || true

### Docker Cleanup (if installed)
- TODO 41: docker system prune -af 2>/dev/null || true
- TODO 42: docker volume prune -f 2>/dev/null || true
- TODO 43: docker image prune -af 2>/dev/null || true
- TODO 44: docker builder prune -af 2>/dev/null || true
- TODO 45: rm -rf ~/.docker/buildx/cache/* 2>/dev/null || true

### Python Environment Cleanup
- TODO 46: rm -rf ~/.local/lib/python*/site-packages/__pycache__/*
- TODO 47: find ~ -name "*.pyc" -delete 2>/dev/null
- TODO 48: find ~ -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
- TODO 49: rm -rf ~/.cache/pip/http/*
- TODO 50: rm -rf ~/.cache/pip/wheels/*

### Node.js Cleanup
- TODO 51: rm -rf ~/.nvm/.cache/*
- TODO 52: rm -rf ~/.yarn/cache/*
- TODO 53: rm -rf ~/.pnpm-store/* 2>/dev/null || true
- TODO 54: find ~ -name "node_modules" -type d -mtime +60 -exec rm -rf {} + 2>/dev/null || true
- TODO 55: npm cache clean --force 2>/dev/null || true

### Git & Version Control Cleanup
- TODO 56: find ~ -name ".git" -type d -exec git -C {}/../ gc --aggressive --prune=now \\; 2>/dev/null || true
- TODO 57: rm -rf ~/.cache/JetBrains/*/caches/* 2>/dev/null || true
- TODO 58: rm -rf ~/.config/Code/CachedData/* 2>/dev/null || true
- TODO 59: rm -rf ~/.config/Code/Cache/* 2>/dev/null || true
- TODO 60: rm -rf ~/.vscode-server/data/CachedData/* 2>/dev/null || true

### System Documentation & Locale
- TODO 61: sudo rm -rf /usr/share/doc/*
- TODO 62: sudo rm -rf /usr/share/man/*
- TODO 63: sudo rm -rf /usr/share/locale/* (keep en_US)
- TODO 64: sudo rm -rf /usr/share/info/*
- TODO 65: sudo rm -rf /usr/share/lintian/*

### Final Cleanup
- TODO 66: sudo rm -rf /root/.cache/*
- TODO 67: sudo rm -rf /root/.local/share/Trash/*
- TODO 68: find /home -name "*.log" -mtime +30 -delete 2>/dev/null
- TODO 69: find /home -name "*.bak" -mtime +30 -delete 2>/dev/null
- TODO 70: df -h && echo "WSL Cleanup complete!" && du -sh /home/*

Report total space freed. Run 'wsl --shutdown' from PowerShell then restart WSL to reclaim memory.
