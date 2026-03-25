# Claude Rules
## Rule 1

On session start run `mcpl; claude mcp list` in PowerShell then disable unnecessary MCPs with `mcp-off <mcp>` and enable only task-relevant ones with `mcpon <mcp>` to minimize resource usage.

## Rule 2

When adding/connecting new MCP servers: 1) Search npm/web for the MCP package name, 2) Install globally with "npm install -g <package-name>", 3) Find the installed path with "npm list -g <package-name>" then locate the main .js file in node_modules, 4) Create a .cmd wrapper file in C:\Users\micha\.claude\ with format: @echo off [newline] "C:\Program Files\nodejs\node.exe" "<full-path-to-index.js>" %* , 5) Add to Claude with "claude mcp add <name> C:\Users\micha\.claude\<name>.cmd -s user", 6) Verify connection with "claude mcp list" - if it shows "Failed to connect" immediately remove it with "claude mcp remove <name> -s user", 7) Only after confirming "Connected" status add the server definition to C:\Users\micha\.claude\mcp-ondemand.ps1 in the $script:MCPServers hashtable with format: "<name>" = @{ wrapper = "<name>.cmd"; description = "<desc>" } , 8) Add the server name to the appropriate category in $script:MCPCategories hashtable, 9) Never keep failed MCPs in config - always test first then add to settings only if working.

## Rule 3

when working wth powershell always make sure to use powershell v5 and that eerythig you make fit v5 version! example: use ; not &&

## Rule 4

After any error or suboptimal approach immediately document what went wrong, why, and the correct solution in `.claude/learned.md` with timestamp, then review this file before starting any new task.

## Rule 5

Work 100% autonomously without ever asking the user to do anything manually - search for information, fix problems, install dependencies, create configs, debug and resolve failures yourself, never stop until the goal is 100% achieved and verified through actual execution/testing, forbidden from ending prematurely or marking tasks done without proof.

## Rule 6

Provide continuous real-time progress updates - announce before touching any file, stream what you're doing, confirm after each action, show outputs immediately, report errors instantly, break goals into granular time-balanced tasks and mark each [x] immediately upon verified completion.

## Rule 7

Before modifying any file trace all dependencies/imports/integrations that could break, build defensive handling for edge cases (null, timeout, missing file, malformed input) into the first implementation, then immediately verify changes worked through tests/commands and use Puppeteer MCP for web UIs - never assume success.

## Rule 8

Minimize file changes by using existing utilities and built-in features over new code, and for any project recursively purge all non-essential content including dependencies, builds, cache, logs, temp files, commented code.

## Rule 9

For F:/tovplay remove all files/folders except tovplay-backend, tovplay-frontend, claude.md, .claude, .logs, .git, purge bloat inside those directories, and achieve tasks WITHOUT modifying the codebases whenever possible - prioritize server configs, environment variables, reverse proxy, middleware, Docker/nginx configs over code changes.

## Rule 10

Implement intelligent caching with invalidation for any reusable operation, never repeat expensive operations, and if something taking >100ms runs frequently optimize it immediately.

## Rule 11

For Claude Code settings modifications use only `C:\Users\micha\.claude.json` and `C:\Users\micha\.claude\settings.json` without unnecessarily removing existing content.

## Rule 12

you lasts steps when every other steps are done are always this: update claude.md with all relevant data for next sessions with full architecture and all... remove what not relevant , than run this exact function alert to alert  me all is done:


