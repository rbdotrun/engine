import { TextContent } from './text-content'
import { ThinkingContent } from './thinking-content'
import { ToolUseContent } from './tool-use-content'
import type { AssistantMessage as AssistantMessageType, ContentBlock } from '../../types'

interface AssistantMessageProps {
  message: AssistantMessageType
  isStreaming?: boolean
}

function ContentBlockRenderer({ block, isStreaming }: { block: ContentBlock; isStreaming: boolean }) {
  switch (block.type) {
    case 'text':
      return <TextContent content={block} isStreaming={isStreaming} />
    case 'thinking':
      return <ThinkingContent content={block} />
    case 'tool_use':
      return <ToolUseContent content={block} />
    default:
      return null
  }
}

export function AssistantMessage({ message, isStreaming = false }: AssistantMessageProps) {
  return (
    <div className="flex flex-col gap-3">
      {message.message.content.map((block, index) => (
        <ContentBlockRenderer
          key={`${block.type}-${index}`}
          block={block}
          isStreaming={isStreaming}
        />
      ))}
    </div>
  )
}
