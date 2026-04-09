param(
    [string]$InitialPrompt = "",
    [string]$Model = "qwen3.5-oll90",
    [string]$OllamaUrl = "http://127.0.0.1:11434",
    [int]$TimeoutSec = 300
)

$ErrorActionPreference = "Continue"

# ============================================================================
# VT100: Enable ANSI escape codes on Windows console
# ============================================================================
try {
    $VT100_TYPE = @'
using System;
using System.Runtime.InteropServices;
public class VT100 {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetStdHandle(int h);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetConsoleMode(IntPtr h, uint m);
    public static bool Enable() {
        IntPtr h = GetStdHandle(-11);
        uint m;
        if (!GetConsoleMode(h, out m)) return false;
        return SetConsoleMode(h, m | 0x0004);
    }
}
'@
    if (-not ([System.Management.Automation.PSTypeName]'VT100').Type) {
        Add-Type -TypeDefinition $VT100_TYPE -Language CSharp -ErrorAction SilentlyContinue
    }
    $script:vt100Enabled = [VT100]::Enable()
} catch {
    $script:vt100Enabled = $false
}

# ANSI color helpers (only used when VT100 enabled)
$script:ESC = [char]27
function Write-Ansi {
    param([string]$Text, [string]$Color = "37")
    if ($script:vt100Enabled) {
        Write-Host "$($script:ESC)[$($Color)m$Text$($script:ESC)[0m" -NoNewline
    } else {
        Write-Host $Text -NoNewline
    }
}

# ============================================================================
# HELPER: Convert PSCustomObject to Hashtable (PS v5.1 ConvertFrom-Json fix)
# ============================================================================
function ConvertTo-Hashtable {
    param([object]$Object)
    if ($Object -is [System.Collections.Hashtable]) { return $Object }
    if ($Object -is [string]) {
        try { $Object = $Object | ConvertFrom-Json } catch { return @{ value = $Object } }
    }
    $ht = @{}
    if ($Object -and $Object.PSObject) {
        $Object.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
    }
    return $ht
}

# ============================================================================
# DISPLAY HELPER: Truncate tool command for clean display
# ============================================================================
function Format-ToolCommand {
    param([string]$Text, [int]$MaxLen = 100)
    if ($Text.Length -gt $MaxLen) {
        return $Text.Substring(0, $MaxLen) + '...'
    }
    return $Text
}

# ============================================================================
# TOOL DISPATCHER: Execute tool calls from the model
# ============================================================================
function Invoke-Tool {
    param(
        [string]$Name,
        [hashtable]$Arguments
    )

    $maxOutputChars = 30000
    $toolTimeoutMs = 60000

    switch ($Name) {
        "run_powershell" {
            $command = $Arguments["command"]
            if (-not $command) { return "[EXEC-PS] ERROR: No command provided" }
            $cmdDisplay = Format-ToolCommand -Text $command
            Write-Host "    " -NoNewline
            Write-Host "> " -ForegroundColor DarkGray -NoNewline
            Write-Host "run_powershell" -ForegroundColor Yellow -NoNewline
            Write-Host "(" -ForegroundColor DarkGray -NoNewline
            Write-Host "$cmdDisplay" -ForegroundColor White -NoNewline
            Write-Host ")" -ForegroundColor DarkGray
            try {
                $tempScript = [System.IO.Path]::GetTempPath() + "oll90_cmd_" + [guid]::NewGuid().ToString("N") + ".ps1"
                $tempOut = [System.IO.Path]::GetTempFileName()
                $tempErr = [System.IO.Path]::GetTempFileName()
                [System.IO.File]::WriteAllText($tempScript, $command, [System.Text.Encoding]::UTF8)
                $proc = Start-Process -FilePath "powershell.exe" `
                    -ArgumentList "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $tempScript `
                    -RedirectStandardOutput $tempOut `
                    -RedirectStandardError $tempErr `
                    -NoNewWindow -PassThru
                $exited = $proc.WaitForExit($toolTimeoutMs)
                if (-not $exited) {
                    try { $proc.Kill() } catch {}
                    return "[EXEC-PS] ERROR: Command timed out after $([int]($toolTimeoutMs/1000))s"
                }
                $stdout = ""
                $stderr = ""
                if (Test-Path $tempOut) { $stdout = [System.IO.File]::ReadAllText($tempOut) }
                if (Test-Path $tempErr) { $stderr = [System.IO.File]::ReadAllText($tempErr) }
                Remove-Item $tempOut, $tempErr, $tempScript -ErrorAction SilentlyContinue
                $result = $stdout
                if ($stderr.Trim()) {
                    $result += "`nSTDERR: $stderr"
                    # Visual STDERR block
                    Write-Host "    " -NoNewline
                    Write-Host "! STDERR" -ForegroundColor Red
                    $stderrLines = ($stderr.Trim() -split "`n" | Select-Object -First 3)
                    foreach ($sl in $stderrLines) {
                        Write-Host "      $($sl.Trim())" -ForegroundColor Red
                    }
                    if (($stderr.Trim() -split "`n").Count -gt 3) {
                        Write-Host "      ..." -ForegroundColor DarkGray
                    }
                    $stderrHint = Analyze-Stderr $stderr
                    if ($stderrHint) {
                        $result += "`n$stderrHint"
                        $hintText = $stderrHint -replace '^\[AGENT HINT\]\s*', ''
                        Write-Host "    " -NoNewline
                        Write-Host "* HINT: " -ForegroundColor Yellow -NoNewline
                        Write-Host "$hintText" -ForegroundColor Yellow
                        # Track for loop detection
                        $errorSig = [regex]::Match($stderr, 'At\s+.+?:(\d+)\s+char:(\d+)').Value
                        if (-not $errorSig) { $errorSig = $stderr.Substring(0, [Math]::Min(100, $stderr.Length)) }
                        [void]$script:recentErrors.Add($errorSig)
                        if ($script:recentErrors.Count -gt $script:errorPatternWindow) { $script:recentErrors.RemoveAt(0) }
                    }
                }
                if (-not $result.Trim()) { $result = "(no output)" }
                if ($result.Length -gt $maxOutputChars) {
                    $result = $result.Substring(0, $maxOutputChars) + "`n... [TRUNCATED at $maxOutputChars chars]"
                }
                # Clean result display
                Write-Host "    " -NoNewline
                Write-Host "< " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($result.Length) chars" -ForegroundColor DarkGray -NoNewline
                Write-Host " | " -ForegroundColor DarkGray -NoNewline
                if ($result -match 'ERROR:' -or $result -match 'STDERR:') {
                    Write-Host "ERROR" -ForegroundColor Red
                } else {
                    Write-Host "OK" -ForegroundColor Green
                }
                $previewLines = ($result -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 2)
                foreach ($pl in $previewLines) {
                    $plTrim = $pl.Trim()
                    if ($plTrim.Length -gt 120) { $plTrim = $plTrim.Substring(0, 120) + '...' }
                    Write-Host "      $plTrim" -ForegroundColor DarkGray
                }
                return "[EXEC-PS] $result"
            } catch {
                return "[EXEC-PS] ERROR: $($_.Exception.Message)"
            }
        }

        "run_cmd" {
            $command = $Arguments["command"]
            if (-not $command) { return "[EXEC-CMD] ERROR: No command provided" }
            $cmdDisplay = Format-ToolCommand -Text $command
            Write-Host "    " -NoNewline
            Write-Host "> " -ForegroundColor DarkGray -NoNewline
            Write-Host "run_cmd" -ForegroundColor Yellow -NoNewline
            Write-Host "(" -ForegroundColor DarkGray -NoNewline
            Write-Host "$cmdDisplay" -ForegroundColor White -NoNewline
            Write-Host ")" -ForegroundColor DarkGray
            try {
                $tempOut = [System.IO.Path]::GetTempFileName()
                $tempErr = [System.IO.Path]::GetTempFileName()
                $proc = Start-Process -FilePath "cmd.exe" `
                    -ArgumentList "/c", $command `
                    -RedirectStandardOutput $tempOut `
                    -RedirectStandardError $tempErr `
                    -NoNewWindow -PassThru
                $exited = $proc.WaitForExit($toolTimeoutMs)
                if (-not $exited) {
                    try { $proc.Kill() } catch {}
                    return "[EXEC-CMD] ERROR: Command timed out after $([int]($toolTimeoutMs/1000))s"
                }
                $stdout = ""
                $stderr = ""
                if (Test-Path $tempOut) { $stdout = [System.IO.File]::ReadAllText($tempOut) }
                if (Test-Path $tempErr) { $stderr = [System.IO.File]::ReadAllText($tempErr) }
                Remove-Item $tempOut, $tempErr -ErrorAction SilentlyContinue
                $result = $stdout
                if ($stderr.Trim()) { $result += "`nSTDERR: $stderr" }
                if (-not $result.Trim()) { $result = "(no output)" }
                if ($result.Length -gt $maxOutputChars) {
                    $result = $result.Substring(0, $maxOutputChars) + "`n... [TRUNCATED at $maxOutputChars chars]"
                }
                Write-Host "    " -NoNewline
                Write-Host "< " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($result.Length) chars" -ForegroundColor DarkGray -NoNewline
                Write-Host " | " -ForegroundColor DarkGray -NoNewline
                if ($result -match 'ERROR:' -or $result -match 'STDERR:') {
                    Write-Host "ERROR" -ForegroundColor Red
                } else {
                    Write-Host "OK" -ForegroundColor Green
                }
                return "[EXEC-CMD] $result"
            } catch {
                return "[EXEC-CMD] ERROR: $($_.Exception.Message)"
            }
        }

        "write_file" {
            $path = $Arguments["path"]
            $content = $Arguments["content"]
            if (-not $path) { return "[WRITE] ERROR: No path provided" }
            if ($null -eq $content) { $content = "" }
            # Sanitize: strip leading .\ from absolute paths (model bug guardrail)
            if ($path -match '^\.[/\\][A-Za-z]:\\') {
                $path = $path.Substring(2)
                Write-Host "  [WARN] Stripped leading '.\\' from absolute path -> $path" -ForegroundColor Yellow
            }

            # PLAN/REPORT INTERCEPTOR: Block write_file when user didn't ask for a file
            $userAskedForFile = $false
            foreach ($m in $script:messages) {
                if ($m.role -eq 'user' -and $m.content) {
                    if ($m.content -match '(?i)(save|write to|create file|output to|log to|\.txt|\.ps1|\.json|\.csv|store to)') {
                        $userAskedForFile = $true; break
                    }
                }
            }
            if (-not $userAskedForFile) {
                $looksLikePlan = ($path -match '(?i)(plan|report|analysis|optimization|summary|result)') -or `
                    ($content.Length -gt 300 -and $content -match '(?i)(plan|phase|step|optimization|summary)')
                if ($looksLikePlan) {
                    Write-Host "    " -NoNewline
                    Write-Host "! BLOCKED " -ForegroundColor Red -NoNewline
                    Write-Host "write_file($path) - user wants output HERE not in file" -ForegroundColor Yellow
                    return "[WRITE] BLOCKED: The user asked to see this in the conversation, not saved to a file. Present the content DIRECTLY in your text response now. Do NOT retry write_file."
                }
            }

            Write-Host "    " -NoNewline
            Write-Host "> " -ForegroundColor DarkGray -NoNewline
            Write-Host "write_file" -ForegroundColor Yellow -NoNewline
            Write-Host "(" -ForegroundColor DarkGray -NoNewline
            Write-Host "$path" -ForegroundColor White -NoNewline
            Write-Host ")" -ForegroundColor DarkGray
            try {
                $dir = [System.IO.Path]::GetDirectoryName($path)
                if ($dir -and -not (Test-Path $dir)) {
                    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
                }
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
                $size = (Get-Item $path).Length
                Write-Host "    " -NoNewline
                Write-Host "< " -ForegroundColor DarkGray -NoNewline
                Write-Host "$size bytes" -ForegroundColor DarkGray -NoNewline
                Write-Host " | " -ForegroundColor DarkGray -NoNewline
                Write-Host "OK" -ForegroundColor Green -NoNewline
                Write-Host " -> $path" -ForegroundColor DarkGray
                return "[WRITE] Successfully wrote $size bytes to $path"
            } catch {
                return "[WRITE] ERROR: $($_.Exception.Message)"
            }
        }

        "read_file" {
            $path = $Arguments["path"]
            if (-not $path) { return "[READ] ERROR: No path provided" }
            # Sanitize: strip leading .\ from absolute paths
            if ($path -match '^\.[/\\][A-Za-z]:\\') {
                $path = $path.Substring(2)
                Write-Host "  [WARN] Stripped leading '.\\' from absolute path -> $path" -ForegroundColor Yellow
            }
            Write-Host "    " -NoNewline
            Write-Host "> " -ForegroundColor DarkGray -NoNewline
            Write-Host "read_file" -ForegroundColor Yellow -NoNewline
            Write-Host "(" -ForegroundColor DarkGray -NoNewline
            Write-Host "$path" -ForegroundColor White -NoNewline
            Write-Host ")" -ForegroundColor DarkGray
            try {
                if (-not (Test-Path $path)) {
                    return "[READ] ERROR: File not found: $path"
                }
                $content = [System.IO.File]::ReadAllText($path)
                if ($content.Length -gt $maxOutputChars) {
                    $content = $content.Substring(0, $maxOutputChars) + "`n... [TRUNCATED at $maxOutputChars chars]"
                }
                Write-Host "    " -NoNewline
                Write-Host "< " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($content.Length) chars" -ForegroundColor DarkGray -NoNewline
                Write-Host " | " -ForegroundColor DarkGray -NoNewline
                Write-Host "OK" -ForegroundColor Green
                return "[READ] $content"
            } catch {
                return "[READ] ERROR: $($_.Exception.Message)"
            }
        }

        "edit_file" {
            $path = $Arguments["path"]
            $oldText = $Arguments["old_text"]
            $newText = $Arguments["new_text"]
            if (-not $path -or -not $oldText) { return "[EDIT] ERROR: path and old_text required" }
            if ($path -match '^\.[/\\][A-Za-z]:\\') { $path = $path.Substring(2) }
            Write-Host "    " -NoNewline
            Write-Host "> " -ForegroundColor DarkGray -NoNewline
            Write-Host "edit_file" -ForegroundColor Yellow -NoNewline
            Write-Host "(" -ForegroundColor DarkGray -NoNewline
            Write-Host "$path" -ForegroundColor White -NoNewline
            Write-Host ")" -ForegroundColor DarkGray
            try {
                if (-not (Test-Path $path)) { return "[EDIT] ERROR: File not found: $path" }
                $content = [System.IO.File]::ReadAllText($path)
                $count = ([regex]::Matches($content, [regex]::Escape($oldText))).Count
                if ($count -eq 0) { return "[EDIT] ERROR: old_text not found in file" }
                if ($count -gt 1) { return "[EDIT] ERROR: old_text found $count times (must be unique)" }
                $newContent = $content.Replace($oldText, $newText)
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($path, $newContent, $utf8NoBom)
                Write-Host "    " -NoNewline
                Write-Host "< " -ForegroundColor DarkGray -NoNewline
                Write-Host "replaced $($oldText.Length) -> $($newText.Length) chars" -ForegroundColor DarkGray -NoNewline
                Write-Host " | " -ForegroundColor DarkGray -NoNewline
                Write-Host "OK" -ForegroundColor Green
                return "[EDIT] Replaced $($oldText.Length) chars with $($newText.Length) chars in $path"
            } catch {
                return "[EDIT] ERROR: $($_.Exception.Message)"
            }
        }

        "list_directory" {
            $path = $Arguments["path"]
            if (-not $path) { return "[LIST] ERROR: No path provided" }
            $recursive = $Arguments["recursive"] -eq $true
            $pattern = if ($Arguments["pattern"]) { $Arguments["pattern"] } else { "*" }
            Write-Host "    " -NoNewline
            Write-Host "> " -ForegroundColor DarkGray -NoNewline
            Write-Host "list_directory" -ForegroundColor Yellow -NoNewline
            Write-Host "(" -ForegroundColor DarkGray -NoNewline
            Write-Host "$path" -ForegroundColor White -NoNewline
            Write-Host ")" -ForegroundColor DarkGray
            try {
                if (-not (Test-Path $path)) { return "[LIST] ERROR: Directory not found: $path" }
                $items = if ($recursive) {
                    Get-ChildItem -Path $path -Filter $pattern -Recurse -ErrorAction SilentlyContinue | Select-Object -First 500
                } else {
                    Get-ChildItem -Path $path -Filter $pattern -ErrorAction SilentlyContinue | Select-Object -First 500
                }
                $lines = @("Directory: $path", "$($items.Count) items", "")
                foreach ($item in $items) {
                    $kind = if ($item.PSIsContainer) { "D" } else { "F" }
                    $sz = if ($item.PSIsContainer) { 0 } else { $item.Length }
                    $szStr = if ($sz -gt 1GB) { "{0:F1} GB" -f ($sz / 1GB) } elseif ($sz -gt 1MB) { "{0:F1} MB" -f ($sz / 1MB) } elseif ($sz -gt 1KB) { "{0:F1} KB" -f ($sz / 1KB) } else { "$sz B" }
                    $mtime = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    $lines += "[$kind] {0,10}  {1}  {2}" -f $szStr, $mtime, $item.Name
                }
                $result = $lines -join "`n"
                Write-Host "    " -NoNewline
                Write-Host "< " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($items.Count) items" -ForegroundColor DarkGray -NoNewline
                Write-Host " | " -ForegroundColor DarkGray -NoNewline
                Write-Host "OK" -ForegroundColor Green
                return "[LIST] $result"
            } catch {
                return "[LIST] ERROR: $($_.Exception.Message)"
            }
        }

        "search_files" {
            $path = $Arguments["path"]
            $pattern = $Arguments["pattern"]
            if (-not $path -or -not $pattern) { return "[SEARCH] ERROR: path and pattern required" }
            $fileGlob = if ($Arguments["file_glob"]) { $Arguments["file_glob"] } else { "*.*" }
            Write-Host "    " -NoNewline
            Write-Host "> " -ForegroundColor DarkGray -NoNewline
            Write-Host "search_files" -ForegroundColor Yellow -NoNewline
            Write-Host "(" -ForegroundColor DarkGray -NoNewline
            Write-Host "/$pattern/" -ForegroundColor White -NoNewline
            Write-Host ")" -ForegroundColor DarkGray
            try {
                if (-not (Test-Path $path)) { return "[SEARCH] ERROR: Directory not found: $path" }
                $regex = [regex]::new($pattern, 'IgnoreCase')
                $matches = @()
                $filesSearched = 0
                $maxResults = 50
                $files = Get-ChildItem -Path $path -Filter $fileGlob -Recurse -File -ErrorAction SilentlyContinue
                foreach ($f in $files) {
                    if ($f.Length -gt 1MB) { continue }
                    $filesSearched++
                    try {
                        $lineNum = 0
                        foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
                            $lineNum++
                            if ($regex.IsMatch($line)) {
                                $preview = if ($line.Length -gt 200) { $line.Substring(0, 200) } else { $line }
                                $matches += "{0}:{1}: {2}" -f $f.FullName, $lineNum, $preview.Trim()
                                if ($matches.Count -ge $maxResults) { break }
                            }
                        }
                    } catch {}
                    if ($matches.Count -ge $maxResults) { break }
                }
                $result = "Searched $filesSearched files in $path`n$($matches.Count) matches for /$pattern/`n`n" + ($matches -join "`n")
                Write-Host "    " -NoNewline
                Write-Host "< " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($matches.Count) matches in $filesSearched files" -ForegroundColor DarkGray -NoNewline
                Write-Host " | " -ForegroundColor DarkGray -NoNewline
                Write-Host "OK" -ForegroundColor Green
                return "[SEARCH] $result"
            } catch {
                return "[SEARCH] ERROR: $($_.Exception.Message)"
            }
        }

        "get_system_info" {
            Write-Host "    " -NoNewline
            Write-Host "> " -ForegroundColor DarkGray -NoNewline
            Write-Host "get_system_info" -ForegroundColor Yellow
            try {
                $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
                $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
                $gpu = ""
                try { $gpu = (nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>$null) } catch {}
                $ramGB = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1MB, 1) } else { 0 }
                $freeGB = if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB, 1) } else { 0 }
                $lines = @(
                    "CPU: $(if($cpu){$cpu.Name}else{'unknown'})"
                    "Cores: $(if($cpu){$cpu.NumberOfCores}else{'?'}) ($(if($cpu){$cpu.NumberOfLogicalProcessors}else{'?'}) logical)"
                    "RAM: $ramGB GB total, $freeGB GB free"
                    "OS: $(if($os){$os.Caption}else{'unknown'}) Build $(if($os){$os.BuildNumber}else{'?'})"
                )
                if ($gpu) { $lines += "GPU: $gpu" }
                foreach ($d in $disks) {
                    $totalGB = [math]::Round($d.Size / 1GB, 1)
                    $freeGB2 = [math]::Round($d.FreeSpace / 1GB, 1)
                    $lines += "Disk $($d.DeviceID) $totalGB GB total, $freeGB2 GB free"
                }
                $result = $lines -join "`n"
                Write-Host "    " -NoNewline
                Write-Host "< " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($lines.Count) items" -ForegroundColor DarkGray -NoNewline
                Write-Host " | " -ForegroundColor DarkGray -NoNewline
                Write-Host "OK" -ForegroundColor Green
                return "[SYSINFO] $result"
            } catch {
                return "[SYSINFO] ERROR: $($_.Exception.Message)"
            }
        }

        "web_fetch" {
            $url = $Arguments["url"]
            if (-not $url) { return "[FETCH] ERROR: No URL provided" }
            Write-Host "    " -NoNewline
            Write-Host "> " -ForegroundColor DarkGray -NoNewline
            Write-Host "web_fetch" -ForegroundColor Yellow -NoNewline
            Write-Host "(" -ForegroundColor DarkGray -NoNewline
            Write-Host (Format-ToolCommand -Text $url -MaxLen 80) -ForegroundColor White -NoNewline
            Write-Host ")" -ForegroundColor DarkGray
            try {
                $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                $text = $resp.Content
                # Strip HTML tags
                $text = [regex]::Replace($text, '<script[^>]*>[\s\S]*?</script>', '', 'IgnoreCase')
                $text = [regex]::Replace($text, '<style[^>]*>[\s\S]*?</style>', '', 'IgnoreCase')
                $text = [regex]::Replace($text, '<[^>]+>', ' ')
                $text = [regex]::Replace($text, '\s+', ' ').Trim()
                if ($text.Length -gt 10000) {
                    $text = $text.Substring(0, 10000) + '... [TRUNCATED]'
                }
                Write-Host "    " -NoNewline
                Write-Host "< " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($text.Length) chars" -ForegroundColor DarkGray -NoNewline
                Write-Host " | " -ForegroundColor DarkGray -NoNewline
                Write-Host "OK" -ForegroundColor Green
                return "[FETCH] $text"
            } catch {
                return "[FETCH] ERROR: $($_.Exception.Message)"
            }
        }

        default {
            return "ERROR: Unknown tool '$Name'"
        }
    }
}

# ============================================================================
# API CALLER: POST to Ollama /api/chat with streaming
# ============================================================================
function Invoke-OllamaChat {
    param(
        [System.Collections.ArrayList]$Messages,
        [array]$Tools,
        [string]$ChatModel,
        [string]$Url,
        [int]$Timeout
    )

    $body = @{
        model    = $ChatModel
        messages = @($Messages)
        tools    = $Tools
        stream   = $true
    }

    $json = $body | ConvertTo-Json -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    $req = [System.Net.HttpWebRequest]::Create("$Url/api/chat")
    $req.Method = "POST"
    $req.ContentType = "application/json; charset=utf-8"
    $req.Timeout = $Timeout * 1000
    $req.ReadWriteTimeout = $Timeout * 1000
    $reqStream = $req.GetRequestStream()
    $reqStream.Write($bytes, 0, $bytes.Length)
    $reqStream.Close()

    $resp = $req.GetResponse()
    $respStream = $resp.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($respStream, [System.Text.Encoding]::UTF8)

    # Streaming state
    $fullContent = ""
    $toolCalls = $null
    $evalCount = 0
    $evalDuration = 0
    $promptEvalCount = 0
    $inThinking = $false
    $tokenCount = 0
    $thinkTokens = 0
    $streamStart = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if (-not $line -or -not $line.Trim()) { continue }

            try {
                $chunk = $line | ConvertFrom-Json
            } catch {
                continue
            }

            $msg = $chunk.message
            $content = ""
            if ($msg -and $msg.content) { $content = $msg.content }

            if ($content) {
                $fullContent += $content
                $tokenCount++

                # Think-tag tracking for real-time display
                $remaining = $content
                while ($remaining) {
                    if (-not $inThinking) {
                        $thinkIdx = $remaining.IndexOf('<think>')
                        if ($thinkIdx -ge 0) {
                            $before = $remaining.Substring(0, $thinkIdx)
                            if ($before) { Write-Host $before -NoNewline -ForegroundColor White }
                            $inThinking = $true
                            $remaining = $remaining.Substring($thinkIdx + 7)
                        } else {
                            # Check partial tag
                            if ('<think>'.StartsWith($remaining) -and $remaining.Length -lt 7) {
                                break  # partial, buffer it
                            }
                            Write-Host $remaining -NoNewline -ForegroundColor White
                            $remaining = ""
                        }
                    } else {
                        $endIdx = $remaining.IndexOf('</think>')
                        if ($endIdx -ge 0) {
                            $thinkContent = $remaining.Substring(0, $endIdx)
                            if ($thinkContent) { $thinkTokens++ }
                            $inThinking = $false
                            $remaining = $remaining.Substring($endIdx + 8)
                        } else {
                            $thinkTokens++
                            $remaining = ""
                        }
                    }
                }
            }

            # Tool calls arrive in final chunk
            if ($msg -and $msg.tool_calls -and $msg.tool_calls.Count -gt 0) {
                $toolCalls = $msg.tool_calls
            }

            # Done chunk
            if ($chunk.done -eq $true) {
                if ($chunk.eval_count) { $evalCount = [int]$chunk.eval_count }
                if ($chunk.eval_duration) { $evalDuration = [long]$chunk.eval_duration }
                if ($chunk.prompt_eval_count) { $promptEvalCount = [int]$chunk.prompt_eval_count }
                break
            }
        }
    } finally {
        $reader.Close()
        $respStream.Close()
        $resp.Close()
        $streamStart.Stop()
    }

    # Calculate tok/s
    $tokPerSec = 0.0
    if ($evalDuration -gt 0) {
        $tokPerSec = $evalCount / ($evalDuration / 1000000000.0)
    }

    # Stats line
    if ($tokenCount -gt 0) {
        Write-Host ""
        Write-Host "  --- " -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0:F1} tok/s" -f $tokPerSec) -ForegroundColor Cyan -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host "$evalCount tokens" -ForegroundColor White -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0:F1}s" -f ($streamStart.Elapsed.TotalSeconds)) -ForegroundColor White -NoNewline
        if ($thinkTokens -gt 0) {
            Write-Host " | " -ForegroundColor DarkGray -NoNewline
            Write-Host "think: $thinkTokens" -ForegroundColor DarkGray -NoNewline
        }
        Write-Host " ---" -ForegroundColor DarkGray
    }

    # Track token usage
    $script:totalPromptTokens += $promptEvalCount
    $script:totalEvalTokens += $evalCount

    # Build response object matching original format
    $result = [PSCustomObject]@{
        message = [PSCustomObject]@{
            role       = "assistant"
            content    = $fullContent
            tool_calls = $toolCalls
        }
        eval_count       = $evalCount
        eval_duration    = $evalDuration
        prompt_eval_count = $promptEvalCount
        tokens_per_sec   = $tokPerSec
    }
    return $result
}

# ============================================================================
# TOOL SCHEMAS: 4 tools for Ollama native tool calling
# ============================================================================
$tools = @(
    @{
        type = "function"
        function = @{
            name = "run_powershell"
            description = "Execute a PowerShell command on Windows 11 Pro. Returns stdout and stderr. Use for ALL system operations: Get-Process, Get-ChildItem, Get-WmiObject, nvidia-smi, Get-NetAdapter, Get-EventLog, registry queries, etc. Chain multiple commands with semicolons (;). Use absolute Windows paths (C:\, F:\)."
            parameters = @{
                type = "object"
                properties = @{
                    command = @{
                        type = "string"
                        description = "The PowerShell command to execute"
                    }
                }
                required = @("command")
            }
        }
    }
    @{
        type = "function"
        function = @{
            name = "run_cmd"
            description = "Execute a CMD.exe command. Use for commands requiring CMD syntax: dir, type, tree, batch files, or programs that behave differently under cmd."
            parameters = @{
                type = "object"
                properties = @{
                    command = @{
                        type = "string"
                        description = "The CMD command to execute"
                    }
                }
                required = @("command")
            }
        }
    }
    @{
        type = "function"
        function = @{
            name = "write_file"
            description = "Write content to a file at the specified absolute Windows path. Creates parent directories automatically. Overwrites existing files."
            parameters = @{
                type = "object"
                properties = @{
                    path = @{
                        type = "string"
                        description = "Absolute file path (e.g. C:\Temp\output.txt)"
                    }
                    content = @{
                        type = "string"
                        description = "The content to write to the file"
                    }
                }
                required = @("path", "content")
            }
        }
    }
    @{
        type = "function"
        function = @{
            name = "read_file"
            description = "Read the entire content of a file at the specified absolute Windows path. Returns the file content as a string."
            parameters = @{
                type = "object"
                properties = @{
                    path = @{
                        type = "string"
                        description = "Absolute file path to read (e.g. C:\Temp\data.txt)"
                    }
                }
                required = @("path")
            }
        }
    }
    @{
        type = "function"
        function = @{
            name = "edit_file"
            description = "Edit a file by replacing exact text. old_text must match exactly once. Use read_file first to see the current content."
            parameters = @{
                type = "object"
                properties = @{
                    path = @{ type = "string"; description = "Absolute file path" }
                    old_text = @{ type = "string"; description = "Exact text to find (must be unique in file)" }
                    new_text = @{ type = "string"; description = "Replacement text" }
                }
                required = @("path", "old_text", "new_text")
            }
        }
    }
    @{
        type = "function"
        function = @{
            name = "list_directory"
            description = "List files and directories with sizes and dates. Returns structured listing. Set recursive=true for subdirectories."
            parameters = @{
                type = "object"
                properties = @{
                    path = @{ type = "string"; description = "Absolute directory path" }
                    recursive = @{ type = "boolean"; description = "If true, list recursively" }
                    pattern = @{ type = "string"; description = "File filter pattern (e.g. *.ps1)" }
                }
                required = @("path")
            }
        }
    }
    @{
        type = "function"
        function = @{
            name = "search_files"
            description = "Search file contents for a regex pattern. Returns matching lines with file paths and line numbers."
            parameters = @{
                type = "object"
                properties = @{
                    path = @{ type = "string"; description = "Directory to search in" }
                    pattern = @{ type = "string"; description = "Regex pattern to search for" }
                    file_glob = @{ type = "string"; description = "File filter (e.g. *.ps1, *.txt). Default: *.*" }
                }
                required = @("path", "pattern")
            }
        }
    }
    @{
        type = "function"
        function = @{
            name = "get_system_info"
            description = "Get a snapshot of system information: CPU, RAM, GPU, disk space, OS version. No parameters needed."
            parameters = @{
                type = "object"
                properties = @{}
            }
        }
    }
    @{
        type = "function"
        function = @{
            name = "web_fetch"
            description = "Fetch a web page via HTTP GET. Returns text content with HTML tags stripped. Max 10K chars."
            parameters = @{
                type = "object"
                properties = @{
                    url = @{ type = "string"; description = "URL to fetch" }
                }
                required = @("url")
            }
        }
    }
)

# ============================================================================
# DISPLAY HELPER: Handle <think> blocks from qwen3.5
# ============================================================================
function Show-AgentResponse {
    param([string]$Content)
    if (-not $Content) { return }

    # Extract and display thinking blocks collapsed to one line
    $thinkPattern = '(?s)<think>(.*?)</think>'
    $thinkMatches = [regex]::Matches($Content, $thinkPattern)
    foreach ($m in $thinkMatches) {
        $thinkText = $m.Groups[1].Value.Trim()
        if ($thinkText) {
            $firstLine = ($thinkText -split "`n")[0].Trim()
            if ($firstLine.Length -gt 80) { $firstLine = $firstLine.Substring(0, 80) + '...' }
            Write-Host "    [thinking] $firstLine" -ForegroundColor DarkGray
        }
    }

    # Display non-think content with visual framing
    $displayContent = [regex]::Replace($Content, $thinkPattern, '').Trim()
    if ($displayContent) {
        Write-Host ""
        Write-Host "  .----- AGENT RESPONSE -------." -ForegroundColor Magenta
        $lines = $displayContent -split "`n"
        foreach ($line in $lines) {
            Write-Host "  | " -ForegroundColor Magenta -NoNewline
            Write-Host "$line" -ForegroundColor White
        }
        Write-Host "  '------------------------------'" -ForegroundColor Magenta
        Write-Host ""
    }
}

# ============================================================================
# STDERR ANALYSIS: Parse PS errors and generate hints for the model
# ============================================================================
function Analyze-Stderr {
    param([string]$Stderr)
    if (-not $Stderr) { return $null }

    # Pattern: "At C:\path\file.ps1:155 char:44" or "At line:155 char:44"
    $parseMatch = [regex]::Match($Stderr, 'At\s+(?:(.+?):)?(\d+)\s+char:(\d+)')
    if ($parseMatch.Success) {
        $filePath = $parseMatch.Groups[1].Value
        $lineNum = [int]$parseMatch.Groups[2].Value
        $charPos = [int]$parseMatch.Groups[3].Value

        $lines = $Stderr -split "`n"
        $errDetail = ($lines | Where-Object { $_ -match 'missing|unexpected|variable|expression|token|string|recognized' } | Select-Object -First 1)
        if (-not $errDetail) { $errDetail = ($lines | Select-Object -Last 1) }

        $hint = "[AGENT HINT] PARSE ERROR at line $lineNum char $charPos"
        if ($filePath) { $hint += " in $filePath" }
        if ($errDetail -match '\$' -or $errDetail -match 'variable' -or $errDetail -match 'expression' -or $errDetail -match 'Variable reference') {
            $hint += ". CAUSE: Unescaped dollar-sign in double-quoted string. FIX: Use single quotes for literal strings, or use the subexpression syntax with dollar-sign-parentheses for variable expansion. Do NOT rewrite with the same approach."
        } else {
            $hint += '. Error: ' + $errDetail.Trim() + '. Read the file at that line to diagnose.'
        }
        return $hint
    }

    if ($Stderr -match 'property cannot be processed because the property "(.+)" already exists') {
        $dupProp = $Matches[1]
        return "[AGENT HINT] DUPLICATE PROPERTY '$dupProp' in Select-Object. You listed '$dupProp' as both a raw property AND as N= in a calculated property @{N='$dupProp'...}. Remove one - use either the plain property name OR the calculated @{N=...}, never both."
    }

    if ($Stderr -match 'Access.+denied|UnauthorizedAccess|PermissionDenied') {
        return "[AGENT HINT] ACCESS DENIED. Try -ErrorAction SilentlyContinue for bulk operations or skip protected items."
    }

    return $null
}

# ============================================================================
# MAIN AGENT LOOP
# ============================================================================

# State
$messages = [System.Collections.ArrayList]::new()
$maxToolIterations = 25

# --- Loop detection state ---
$script:recentErrors = [System.Collections.ArrayList]::new()
$script:maxRepeatedErrors = 3
$script:errorPatternWindow = 5

# --- Token tracking ---
$script:totalPromptTokens = 0
$script:totalEvalTokens = 0
$script:contextLimit = 131072

# Detect GPU for banner
$gpuName = "unknown"
try { $gpuLine = (nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>$null); if ($gpuLine) { $gpuName = $gpuLine.Trim() } } catch {}

# Banner
$vtStatus = if ($script:vt100Enabled) { "VT100 ON" } else { "VT100 OFF" }
Write-Host ""
Write-Host "  +================================================================+" -ForegroundColor DarkGray
Write-Host "  |   " -ForegroundColor DarkGray -NoNewline
Write-Host "OLL90 AUTONOMOUS AGENT  v2.0" -ForegroundColor Green -NoNewline
Write-Host "                             |" -ForegroundColor DarkGray
Write-Host "  |   " -ForegroundColor DarkGray -NoNewline
Write-Host "Model   : " -ForegroundColor DarkGray -NoNewline
Write-Host "$Model" -ForegroundColor Cyan -NoNewline
$pad = 51 - $Model.Length; if ($pad -lt 0) { $pad = 0 }
Write-Host (" " * $pad) -NoNewline
Write-Host "|" -ForegroundColor DarkGray
Write-Host "  |   " -ForegroundColor DarkGray -NoNewline
$gpuDisplay = $gpuName
if ($gpuDisplay.Length -gt 49) { $gpuDisplay = $gpuDisplay.Substring(0, 49) }
Write-Host "GPU     : " -ForegroundColor DarkGray -NoNewline
Write-Host "$gpuDisplay" -ForegroundColor Magenta -NoNewline
$pad2 = 51 - $gpuDisplay.Length; if ($pad2 -lt 0) { $pad2 = 0 }
Write-Host (" " * $pad2) -NoNewline
Write-Host "|" -ForegroundColor DarkGray
Write-Host "  |   " -ForegroundColor DarkGray -NoNewline
Write-Host "Context : 128K | Streaming ON | $vtStatus" -ForegroundColor White -NoNewline
$pad3 = 48 - ("128K | Streaming ON | $vtStatus").Length; if ($pad3 -lt 0) { $pad3 = 0 }
Write-Host (" " * $pad3) -NoNewline
Write-Host "|" -ForegroundColor DarkGray
Write-Host "  |   " -ForegroundColor DarkGray -NoNewline
Write-Host "Tools[9]: " -ForegroundColor DarkGray -NoNewline
Write-Host "run_powershell run_cmd write_file read_file" -ForegroundColor Yellow -NoNewline
Write-Host "  |" -ForegroundColor DarkGray
Write-Host "  |             " -ForegroundColor DarkGray -NoNewline
Write-Host "edit_file list_directory search_files" -ForegroundColor Yellow -NoNewline
Write-Host "       |" -ForegroundColor DarkGray
Write-Host "  |             " -ForegroundColor DarkGray -NoNewline
Write-Host "get_system_info web_fetch" -ForegroundColor Yellow -NoNewline
Write-Host "                    |" -ForegroundColor DarkGray
Write-Host "  |   " -ForegroundColor DarkGray -NoNewline
Write-Host "Commands: /exit /clear /history /tools /stats" -ForegroundColor White -NoNewline
Write-Host "         |" -ForegroundColor DarkGray
Write-Host "  +================================================================+" -ForegroundColor DarkGray
Write-Host ""

# Handle initial prompt
$firstInput = $null
if ($InitialPrompt -ne "") {
    $firstInput = $InitialPrompt
    Write-Host "oll90> $firstInput" -ForegroundColor Cyan
}

# Outer REPL loop
while ($true) {
    # Get user input
    if ($firstInput) {
        $userInput = $firstInput
        $firstInput = $null
    } else {
        Write-Host -NoNewline "oll90> " -ForegroundColor Cyan
        $userInput = Read-Host
    }

    # Skip empty input
    if (-not $userInput -or $userInput.Trim() -eq "") { continue }

    # Handle slash commands
    $trimmed = $userInput.Trim().ToLower()
    if ($trimmed -eq "/exit" -or $trimmed -eq "/quit") {
        Write-Host "[SYSTEM] Agent session ended." -ForegroundColor Green
        break
    }
    if ($trimmed -eq "/clear") {
        $messages.Clear()
        Write-Host "[SYSTEM] Conversation history cleared." -ForegroundColor Green
        continue
    }
    if ($trimmed -eq "/history") {
        $msgCount = $messages.Count
        $totalChars = 0
        foreach ($m in $messages) {
            if ($m.content) { $totalChars += $m.content.ToString().Length }
        }
        Write-Host "[SYSTEM] Messages: $msgCount | Est. chars: $totalChars | Est. tokens: ~$([int]($totalChars / 4))" -ForegroundColor Green
        continue
    }
    if ($trimmed -eq "/tools") {
        Write-Host "[SYSTEM] Available tools:" -ForegroundColor Green
        foreach ($t in $tools) { Write-Host "  - $($t.function.name): $($t.function.description.Substring(0, [Math]::Min(80, $t.function.description.Length)))..." -ForegroundColor White }
        continue
    }
    if ($trimmed -eq "/stats") {
        $estTokens = $script:totalPromptTokens + $script:totalEvalTokens
        $pct = if ($script:contextLimit -gt 0) { [math]::Round(($estTokens / $script:contextLimit) * 100, 1) } else { 0 }
        Write-Host "[SYSTEM] Token usage: ~$([int]($estTokens/1000))K / $([int]($script:contextLimit/1000))K ($pct%)" -ForegroundColor Green
        Write-Host "[SYSTEM] Messages: $($messages.Count)" -ForegroundColor Green
        continue
    }

    # Add user message
    [void]$messages.Add(@{ role = "user"; content = $userInput })

    # Inner tool-calling loop
    $iteration = 0
    $taskStartTime = Get-Date
    $script:recentErrors.Clear()
    $script:thinkingRePrompted = $false
    $script:shallowScanRePrompted = $false
    $turnToolCalls = 0
    while ($iteration -lt $maxToolIterations) {
        $iteration++
        $elapsed = ((Get-Date) - $taskStartTime).ToString("mm\:ss")
        $estTokens = $script:totalPromptTokens + $script:totalEvalTokens
        $tokUsage = "~$([int]($estTokens/1000))K/$([int]($script:contextLimit/1000))K"
        Write-Host ""
        Write-Host "  ------ " -ForegroundColor DarkGray -NoNewline
        Write-Host "Step $iteration" -ForegroundColor Cyan -NoNewline
        Write-Host "/$maxToolIterations" -ForegroundColor DarkGray -NoNewline
        Write-Host " ---- " -ForegroundColor DarkGray -NoNewline
        Write-Host "$elapsed" -ForegroundColor White -NoNewline
        Write-Host " ---- " -ForegroundColor DarkGray -NoNewline
        Write-Host "$tokUsage" -ForegroundColor DarkGray -NoNewline
        Write-Host " ------" -ForegroundColor DarkGray

        # --- CONTEXT AUTO-COMPACTION at 85% ---
        $estChars = 0
        foreach ($m in $messages) {
            if ($m.content) { $estChars += $m.content.ToString().Length }
        }
        $estTokensNow = [int]($estChars / 4)
        $compactThreshold = [int]($script:contextLimit * 0.85)
        if ($estTokensNow -gt $compactThreshold -and $messages.Count -gt 10) {
            Write-Host "  [CONTEXT] " -ForegroundColor Yellow -NoNewline
            Write-Host "~$([int]($estTokensNow/1000))K tokens exceeds 85% threshold. Compacting..." -ForegroundColor Yellow
            # Keep: system (index 0) + last 8 messages
            $keepCount = 8
            $systemMsg = $messages[0]
            $middleCount = $messages.Count - 1 - $keepCount
            if ($middleCount -gt 0) {
                $middleText = ""
                for ($mi = 1; $mi -le $middleCount; $mi++) {
                    $mmsg = $messages[$mi]
                    $role = $mmsg.role
                    $txt = if ($mmsg.content) { $mmsg.content.ToString() } else { "" }
                    if ($txt.Length -gt 200) { $txt = $txt.Substring(0, 200) + '...' }
                    $middleText += "[$role] $txt`n"
                }
                $summaryMsg = @{
                    role = "system"
                    content = "[CONTEXT COMPACTED] Previous conversation summary ($middleCount messages compacted):`n$middleText"
                }
                $tail = [System.Collections.ArrayList]::new()
                for ($ti = ($messages.Count - $keepCount); $ti -lt $messages.Count; $ti++) {
                    [void]$tail.Add($messages[$ti])
                }
                $messages.Clear()
                [void]$messages.Add($systemMsg)
                [void]$messages.Add($summaryMsg)
                foreach ($t in $tail) { [void]$messages.Add($t) }
                Write-Host "  [CONTEXT] Compacted to $($messages.Count) messages" -ForegroundColor Green
            }
        }

        # Call Ollama API
        $response = $null
        try {
            $response = Invoke-OllamaChat -Messages $messages -Tools $tools -ChatModel $Model -Url $OllamaUrl -Timeout $TimeoutSec
        } catch {
            $errMsg = $_.Exception.Message
            if ($errMsg -match "Unable to connect" -or $errMsg -match "ConnectFailure") {
                Write-Host "[ERROR] Cannot reach Ollama at $OllamaUrl. Is it running?" -ForegroundColor Red
            } else {
                Write-Host "[ERROR] API call failed: $errMsg" -ForegroundColor Red
            }
            # Remove the user message so they can retry
            if ($messages.Count -gt 0) { $messages.RemoveAt($messages.Count - 1) }
            break
        }

        # Validate response
        if (-not $response -or -not $response.message) {
            Write-Host "[ERROR] Unexpected response format from Ollama" -ForegroundColor Red
            break
        }

        $msg = $response.message

        # Check for tool calls
        $hasToolCalls = $false
        if ($msg.tool_calls -and $msg.tool_calls.Count -gt 0) {
            $hasToolCalls = $true
        }

        if ($hasToolCalls) {
            # Append the assistant message (with tool_calls) to history
            $assistantMsg = @{
                role = "assistant"
                content = if ($msg.content) { $msg.content } else { "" }
                tool_calls = @($msg.tool_calls)
            }
            [void]$messages.Add($assistantMsg)

            # Show any content the assistant said before calling tools
            if ($msg.content -and $msg.content.Trim()) {
                Show-AgentResponse $msg.content
            }

            # Track tool calls for shallow-scan detection
            $turnToolCalls += $msg.tool_calls.Count

            # Execute each tool call
            foreach ($tc in $msg.tool_calls) {
                $toolName = $tc.function.name
                $toolArgs = $tc.function.arguments
                # Handle arguments as string or object
                if ($toolArgs -is [string]) {
                    try { $toolArgs = $toolArgs | ConvertFrom-Json } catch { $toolArgs = @{ command = $toolArgs } }
                }
                $toolArgsHt = ConvertTo-Hashtable $toolArgs

                # Execute the tool
                $toolResult = Invoke-Tool -Name $toolName -Arguments $toolArgsHt

                # Append tool result to messages
                [void]$messages.Add(@{
                    role = "tool"
                    content = $toolResult
                })
            }

            # --- STUCK DETECTION ---
            if ($script:recentErrors.Count -ge $script:maxRepeatedErrors) {
                $lastN = @($script:recentErrors | Select-Object -Last $script:maxRepeatedErrors)
                $uniqueErrors = @($lastN | Sort-Object -Unique)
                if ($uniqueErrors.Count -eq 1) {
                    Write-Host ""
                    Write-Host "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
                    Write-Host "   STUCK DETECTED - Same error $($script:maxRepeatedErrors)x in a row" -ForegroundColor Red
                    Write-Host "   Forcing new approach..." -ForegroundColor Yellow
                    Write-Host "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
                    Write-Host ""
                    $stuckMsg = "[SYSTEM] WARNING: You have made the same error $($script:maxRepeatedErrors) times in a row. You MUST try a completely different approach. Switch to single-quoted strings with concatenation (+), avoid all variable interpolation in double quotes, and simplify the script."
                    [void]$messages.Add(@{ role = "user"; content = $stuckMsg })
                    $script:recentErrors.Clear()
                }
            }

            # Continue the inner loop - let the model see the tool results
            continue
        } else {
            # No tool calls - just content response
            [void]$messages.Add(@{
                role = "assistant"
                content = if ($msg.content) { $msg.content } else { "" }
            })

            $content = $msg.content
            $cleanContent = ""
            if ($content) { $cleanContent = [regex]::Replace($content, '(?s)<think>.*?</think>', '').Trim() }
            $onlyThinking = (-not $cleanContent -and $content -and $content -match '(?s)<think>')

            # --- SHALLOW SCAN CHECK (one re-prompt per turn) ---
            $isDeepScanTask = $userInput -match '(?i)(scan deeply|deep scan|deeply scan)'
            if ($isDeepScanTask -and $turnToolCalls -lt 5 -and -not $script:shallowScanRePrompted) {
                $script:shallowScanRePrompted = $true
                Write-Host ""
                Write-Host "  [SHALLOW SCAN: $turnToolCalls tool calls - requiring deeper scan]" -ForegroundColor Yellow
                Write-Host ""
                $rePrompt = "[SYSTEM] Your scan was too shallow ($turnToolCalls tool calls). The task requires a DEEP scan. Call run_powershell multiple more times to gather: CPU specs, GPU details (nvidia-smi), RAM, storage, network adapters, top processes, temperatures. Make at least 5+ more tool calls before writing your plan."
                [void]$messages.Add(@{ role = "user"; content = $rePrompt })
                continue
            }

            # --- THINKING-ONLY CHECK (one re-prompt per turn) ---
            if ($onlyThinking -and -not $script:thinkingRePrompted) {
                $script:thinkingRePrompted = $true
                Write-Host ""
                Write-Host "  [thinking-only response - prompting for visible output]" -ForegroundColor Yellow
                Write-Host ""
                $rePrompt = "[SYSTEM] CRITICAL: Your last response was ENTIRELY inside <think> blocks. The user CANNOT see <think> content. Output your response as PLAIN VISIBLE TEXT right now - no <think> tags."
                [void]$messages.Add(@{ role = "user"; content = $rePrompt })
                continue
            }

            # Content already streamed inline, just add framing
            $content = $msg.content
            $cleanContent2 = ""
            if ($content) { $cleanContent2 = [regex]::Replace($content, '(?s)<think>.*?</think>', '').Trim() }
            if (-not $cleanContent2 -and $turnToolCalls -gt 0) {
                # No visible response but tools ran - add note
                Write-Host ""
                Write-Host "  [agent completed tools without text summary]" -ForegroundColor DarkGray
            }
            Write-Host ""
            break
        }
    }

    if ($iteration -ge $maxToolIterations) {
        Write-Host "[WARN] Reached max tool iterations ($maxToolIterations). Breaking out." -ForegroundColor DarkYellow
    }

    # Task summary
    $taskDuration = ((Get-Date) - $taskStartTime).ToString("mm\:ss")
    $hadErrors = ($script:recentErrors.Count -gt 0)
    $estTokFinal = $script:totalPromptTokens + $script:totalEvalTokens
    $tokPctFinal = if ($script:contextLimit -gt 0) { [math]::Round(($estTokFinal / $script:contextLimit) * 100, 1) } else { 0 }
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor DarkGray
    if ($hadErrors) {
        Write-Host "   COMPLETED WITH ERRORS" -ForegroundColor Yellow
    } else {
        Write-Host "   COMPLETED" -ForegroundColor Green
    }
    Write-Host "   Steps: " -ForegroundColor DarkGray -NoNewline
    Write-Host "$iteration" -ForegroundColor White -NoNewline
    Write-Host "   Tools: " -ForegroundColor DarkGray -NoNewline
    Write-Host "$turnToolCalls" -ForegroundColor White -NoNewline
    Write-Host "   Time: " -ForegroundColor DarkGray -NoNewline
    Write-Host "$taskDuration" -ForegroundColor White -NoNewline
    Write-Host "   Ctx: " -ForegroundColor DarkGray -NoNewline
    Write-Host "~$([int]($estTokFinal/1000))K ($tokPctFinal%)" -ForegroundColor Cyan
    if ($hadErrors) {
        Write-Host "   Errors: " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($script:recentErrors.Count)" -ForegroundColor Red
    } else {
        Write-Host ""
    }
    Write-Host "  ================================================" -ForegroundColor DarkGray
    Write-Host ""
    $script:recentErrors.Clear()
}
