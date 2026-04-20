# OpenClaw Mega Fix Script - 40+ Commands for Maintenance & Repair
# Generated: 2026-03-12
# Purpose: Comprehensive OpenClaw diagnostics, repair, and maintenance

Write-Host "🦞 OpenClaw Mega Fix - Starting comprehensive maintenance..." -ForegroundColor Cyan

# 1. CONFIG & VALIDATION
Write-Host "`n[1/40] Validating config..." -ForegroundColor Yellow
openclaw config validate

# 2. DOCTOR WITH FIXES
Write-Host "`n[2/40] Running doctor with auto-fix..." -ForegroundColor Yellow
openclaw doctor --fix --yes

# 3. DOCTOR DEEP SCAN
Write-Host "`n[3/40] Running deep system scan..." -ForegroundColor Yellow
openclaw doctor --deep

# 4. SECURITY AUDIT
Write-Host "`n[4/40] Running security audit..." -ForegroundColor Yellow
openclaw security audit

# 5. SECURITY AUDIT WITH FIX
Write-Host "`n[5/40] Running security audit with auto-fix..." -ForegroundColor Yellow
openclaw security audit --fix

# 6. GATEWAY STATUS
Write-Host "`n[6/40] Checking gateway status..." -ForegroundColor Yellow
openclaw gateway status

# 7. GATEWAY HEALTH
Write-Host "`n[7/40] Checking gateway health..." -ForegroundColor Yellow
openclaw gateway health

# 8. GATEWAY PROBE
Write-Host "`n[8/40] Probing gateway reachability..." -ForegroundColor Yellow
openclaw gateway probe

# 9. CHANNELS STATUS
Write-Host "`n[9/40] Checking channels status..." -ForegroundColor Yellow
openclaw channels status

# 10. CHANNELS DEEP STATUS
Write-Host "`n[10/40] Checking channels deep status..." -ForegroundColor Yellow
openclaw channels status --deep

# 11. CHANNELS CAPABILITIES
Write-Host "`n[11/40] Checking channel capabilities..." -ForegroundColor Yellow
openclaw channels capabilities

# 12. BROWSER STATUS
Write-Host "`n[12/40] Checking browser status..." -ForegroundColor Yellow
openclaw browser status

# 13. BROWSER START
Write-Host "`n[13/40] Starting browser service..." -ForegroundColor Yellow
openclaw browser start

# 14. BROWSER PROFILES LIST
Write-Host "`n[14/40] Listing browser profiles..." -ForegroundColor Yellow
openclaw browser profiles

# 15. SANDBOX LIST
Write-Host "`n[15/40] Listing sandbox containers..." -ForegroundColor Yellow
openclaw sandbox list

# 16. SANDBOX EXPLAIN
Write-Host "`n[16/40] Explaining sandbox policy..." -ForegroundColor Yellow
openclaw sandbox explain

# 17. MEMORY STATUS
Write-Host "`n[17/40] Checking memory index status..." -ForegroundColor Yellow
openclaw memory status

# 18. MEMORY DEEP STATUS
Write-Host "`n[18/40] Checking memory provider status..." -ForegroundColor Yellow
openclaw memory status --deep

# 19. MEMORY REINDEX
Write-Host "`n[19/40] Reindexing memory files..." -ForegroundColor Yellow
openclaw memory index

# 20. PLUGINS LIST
Write-Host "`n[20/40] Listing plugins..." -ForegroundColor Yellow
openclaw plugins list

# 21. PLUGINS DOCTOR
Write-Host "`n[21/40] Running plugin diagnostics..." -ForegroundColor Yellow
openclaw plugins doctor

# 22. SKILLS CHECK
Write-Host "`n[22/40] Checking skills requirements..." -ForegroundColor Yellow
openclaw skills check

# 23. SKILLS LIST
Write-Host "`n[23/40] Listing skills..." -ForegroundColor Yellow
openclaw skills list

# 24. MODELS STATUS
Write-Host "`n[24/40] Checking model configuration..." -ForegroundColor Yellow
openclaw models status

# 25. MODELS LIST
Write-Host "`n[25/40] Listing available models..." -ForegroundColor Yellow
openclaw models list

# 26. UPDATE STATUS
Write-Host "`n[26/40] Checking update status..." -ForegroundColor Yellow
openclaw update status

# 27. SESSIONS LIST
Write-Host "`n[27/40] Listing sessions..." -ForegroundColor Yellow
openclaw sessions list

# 28. HEALTH CHECK
Write-Host "`n[28/40] Fetching health..." -ForegroundColor Yellow
openclaw health

# 29. STATUS CHECK
Write-Host "`n[29/40] Checking overall status..." -ForegroundColor Yellow
openclaw status

# 30. HOOKS LIST
Write-Host "`n[30/40] Listing hooks..." -ForegroundColor Yellow
openclaw hooks list

# 31. APPROVALS LIST
Write-Host "`n[31/40] Listing approvals..." -ForegroundColor Yellow
openclaw approvals list

# 32. CRON LIST
Write-Host "`n[32/40] Listing cron jobs..." -ForegroundColor Yellow
openclaw cron list

# 33. NODES LIST
Write-Host "`n[33/40] Listing nodes..." -ForegroundColor Yellow
openclaw nodes list

# 34. GATEWAY DISCOVER
Write-Host "`n[34/40] Discovering gateways..." -ForegroundColor Yellow
openclaw gateway discover

# 35. DIRECTORY LOOKUP SELF
Write-Host "`n[35/40] Looking up directory self..." -ForegroundColor Yellow
openclaw directory lookup --self

# 36. BACKUP CREATE
Write-Host "`n[36/40] Creating backup..." -ForegroundColor Yellow
openclaw backup create

# 37. CONFIG FILE CHECK
Write-Host "`n[37/40] Displaying config file path..." -ForegroundColor Yellow
openclaw config file

# 38. GATEWAY RESTART (if needed)
Write-Host "`n[38/40] Restarting gateway to apply fixes..." -ForegroundColor Yellow
openclaw gateway restart

# 39. BROWSER STOP/START CYCLE
Write-Host "`n[39/40] Cycling browser service..." -ForegroundColor Yellow
openclaw browser stop
Start-Sleep -Seconds 2
openclaw browser start

# 40. FINAL HEALTH CHECK
Write-Host "`n[40/40] Final health check..." -ForegroundColor Yellow
openclaw health

# 41. FINAL GATEWAY STATUS
Write-Host "`n[41/40] Final gateway status..." -ForegroundColor Yellow
openclaw gateway status

# 42. FINAL BROWSER STATUS
Write-Host "`n[42/40] Final browser status..." -ForegroundColor Yellow
openclaw browser status

# 43. FINAL CHANNELS STATUS
Write-Host "`n[43/40] Final channels status..." -ForegroundColor Yellow
openclaw channels status

Write-Host "`n✅ OpenClaw Mega Fix Complete!" -ForegroundColor Green
Write-Host "Review output above for any remaining issues." -ForegroundColor Cyan
