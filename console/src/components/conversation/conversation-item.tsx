import { AlertCircle } from 'lucide-react'
import { UserMessage } from './user-message'
import { SystemMessage } from './system-message'
import { AssistantMessage } from './assistant-message'
import { ResultMessage } from './result-message'
import type { ConversationEntry } from '../../types'

interface ConversationItemProps {
  entry: ConversationEntry
  isStreaming?: boolean
}

export function ConversationItem({ entry, isStreaming = false }: ConversationItemProps) {
  if (entry.error || !entry.parsed) {
    return (
      <div className="flex items-start gap-2 text-red-400 text-xs p-2 bg-red-500/10 rounded-lg border border-red-500/30">
        <AlertCircle size={14} className="flex-shrink-0 mt-0.5" />
        <div className="flex flex-col gap-1">
          <span>{entry.error || 'Failed to parse message'}</span>
          <code className="text-red-300/60 text-xs break-all">{entry.raw}</code>
        </div>
      </div>
    )
  }

  const { parsed } = entry

  switch (parsed.type) {
    case 'user':
      return <UserMessage message={parsed} />
    case 'system':
      return <SystemMessage message={parsed} />
    case 'assistant':
      return <AssistantMessage message={parsed} isStreaming={isStreaming} />
    case 'result':
      return <ResultMessage message={parsed} />
    default:
      return null
  }
}
