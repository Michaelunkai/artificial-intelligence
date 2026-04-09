import MarkdownRenderer from '../markdown/MarkdownRenderer'

export default function AgentMessage({ content }) {
  if (!content || !content.trim()) return null

  // Strip <think> blocks for display
  const clean = content.replace(/<think>[\s\S]*?<\/think>/g, '').trim()
  if (!clean) return null

  return (
    <div className="px-4 py-2">
      <div className="border-l-2 border-terminal-magenta pl-3">
        <div className="text-[10px] text-terminal-magenta mb-1">AGENT RESPONSE</div>
        <div className="text-sm">
          <MarkdownRenderer content={clean} />
        </div>
      </div>
    </div>
  )
}
