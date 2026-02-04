import { Markdown } from './markdown'
import type { TextContent as TextContentType } from '../../types'

interface TextContentProps {
  content: TextContentType
  isStreaming?: boolean
}

export function TextContent({ content, isStreaming = false }: TextContentProps) {
  return (
    <div className="prose prose-sm prose-invert max-w-none text-neutral-200">
      <Markdown isStreaming={isStreaming}>{content.text}</Markdown>
    </div>
  )
}
