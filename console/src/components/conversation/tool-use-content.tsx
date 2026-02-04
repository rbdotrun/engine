import { Wrench } from 'lucide-react'
import type { ToolUseContent as ToolUseContentType } from '../../types'

interface ToolUseContentProps {
  content: ToolUseContentType
}

export function ToolUseContent({ content }: ToolUseContentProps) {
  return (
    <div className="rounded-lg border border-blue-500/30 bg-blue-500/5 p-3">
      <div className="flex items-center gap-2 text-blue-400 text-xs font-medium mb-2">
        <Wrench size={14} />
        <span>{content.name}</span>
      </div>
      <pre className="text-xs text-blue-200/80 whitespace-pre-wrap break-words font-mono m-0 overflow-x-auto">
        {JSON.stringify(content.input, null, 2)}
      </pre>
    </div>
  )
}
