import { useState } from 'react'

function truncate(str, max = 100) {
  if (!str) return ''
  return str.length > max ? str.slice(0, max) + '...' : str
}

function formatDuration(ms) {
  if (!ms) return ''
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(1)}s`
}

export default function ToolCallBlock({ name, args, status, result, stderr, hint, durationMs, outputChars }) {
  const [expanded, setExpanded] = useState(false)

  const argsPreview = args?.command
    ? truncate(args.command, 80)
    : args?.path
      ? truncate(args.path, 80)
      : JSON.stringify(args || {}).slice(0, 80)

  const statusColors = {
    running: 'text-terminal-yellow',
    complete: 'text-terminal-green',
    error: 'text-terminal-red',
    blocked: 'text-terminal-red',
  }

  const statusLabels = {
    running: 'running...',
    complete: 'OK',
    error: 'ERROR',
    blocked: 'BLOCKED',
  }

  return (
    <div className="px-4 py-1">
      <div className="border border-terminal-border rounded bg-terminal-surface/50 text-xs">
        {/* Header */}
        <div
          className="flex items-center gap-2 px-3 py-1.5 cursor-pointer hover:bg-terminal-border/30"
          onClick={() => setExpanded(!expanded)}
        >
          {status === 'running' && (
            <span className="spinner inline-block w-3 h-3 border border-terminal-yellow border-t-transparent rounded-full" />
          )}
          <span className="text-terminal-yellow">&gt;</span>
          <span className="text-terminal-yellow">{name}</span>
          <span className="text-terminal-muted truncate flex-1">({argsPreview})</span>
          <span className={statusColors[status] || 'text-terminal-muted'}>
            {statusLabels[status] || status}
          </span>
          {durationMs > 0 && (
            <span className="text-terminal-muted">[{formatDuration(durationMs)}]</span>
          )}
          {outputChars > 0 && (
            <span className="text-terminal-muted">{outputChars} chars</span>
          )}
          <span className="text-terminal-muted">{expanded ? '-' : '+'}</span>
        </div>

        {/* Expanded content */}
        {expanded && (
          <div className="border-t border-terminal-border px-3 py-2 max-h-80 overflow-y-auto">
            {/* Args */}
            <div className="mb-2">
              <div className="text-terminal-muted mb-1">Arguments:</div>
              <pre className="text-terminal-text whitespace-pre-wrap break-all text-[11px]">
                {JSON.stringify(args, null, 2)}
              </pre>
            </div>

            {/* Result */}
            {result && (
              <div className="mb-2">
                <div className="text-terminal-muted mb-1">Output:</div>
                <pre className="text-terminal-text whitespace-pre-wrap break-all text-[11px] max-h-48 overflow-y-auto">
                  {result}
                </pre>
              </div>
            )}

            {/* Stderr */}
            {stderr && (
              <div className="mb-2">
                <div className="text-terminal-red mb-1">STDERR:</div>
                <pre className="text-terminal-red/80 whitespace-pre-wrap break-all text-[11px]">
                  {stderr}
                </pre>
              </div>
            )}

            {/* Hint */}
            {hint && (
              <div className="text-terminal-yellow text-[11px]">{hint}</div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
