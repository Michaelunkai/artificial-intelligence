export default function UserMessage({ content }) {
  return (
    <div className="px-4 py-2">
      <div className="flex items-start gap-2">
        <span className="text-terminal-cyan font-bold text-sm shrink-0">oll90&gt;</span>
        <pre className="text-terminal-text whitespace-pre-wrap break-words text-sm m-0">{content}</pre>
      </div>
    </div>
  )
}
