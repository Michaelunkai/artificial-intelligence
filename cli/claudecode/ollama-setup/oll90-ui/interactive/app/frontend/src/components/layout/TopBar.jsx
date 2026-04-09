import useStatusStore from '../../stores/statusStore'

export default function TopBar() {
  const { gpuName, gpuUtil, vramUsed, vramTotal, gpuTemp, modelName, tokensPerSec, connected } = useStatusStore()
  const vramGB = (vramUsed / 1024).toFixed(1)
  const vramTotalGB = (vramTotal / 1024).toFixed(1)
  const vramPct = vramTotal > 0 ? (vramUsed / vramTotal * 100) : 0
  const vramColor = vramPct > 95 ? 'text-terminal-red' : vramPct > 80 ? 'text-terminal-yellow' : 'text-terminal-green'

  return (
    <div className="flex items-center justify-between px-4 py-1.5 bg-terminal-surface border-b border-terminal-border text-xs">
      <div className="flex items-center gap-4">
        <span className="text-terminal-magenta font-bold">OLL90</span>
        <span className="text-terminal-muted">{modelName}</span>
        <span className="text-terminal-muted">|</span>
        <span className="text-terminal-cyan">GPU {gpuUtil}%</span>
        <span className={vramColor}>VRAM {vramGB}/{vramTotalGB} GB</span>
        {gpuTemp > 0 && <span className="text-terminal-muted">{gpuTemp}C</span>}
        {tokensPerSec > 0 && (
          <>
            <span className="text-terminal-muted">|</span>
            <span className="text-terminal-green">{tokensPerSec} tok/s</span>
          </>
        )}
      </div>
      <div className="flex items-center gap-2">
        <span className={`inline-block w-2 h-2 rounded-full ${connected ? 'bg-terminal-green' : 'bg-terminal-red'}`} />
        <span className="text-terminal-muted">{connected ? 'connected' : 'disconnected'}</span>
      </div>
    </div>
  )
}
