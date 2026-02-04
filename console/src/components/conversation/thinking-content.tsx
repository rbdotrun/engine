import { Lightbulb } from 'lucide-react'
import type { ThinkingContent as ThinkingContentType } from '../../types'

interface ThinkingContentProps {
  content: ThinkingContentType
}

export function ThinkingContent({ content }: ThinkingContentProps) {
  return (
    <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-3">
      <div className="flex items-center gap-2 text-amber-500 text-xs font-medium mb-2">
        <Lightbulb size={14} />
        <span>Thinking</span>
      </div>
      <pre className="text-xs text-amber-200/80 whitespace-pre-wrap break-words font-mono m-0">
        {content.thinking}
      </pre>
    </div>
  )
}
