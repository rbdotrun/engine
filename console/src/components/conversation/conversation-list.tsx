import { useMemo } from 'react'
import { ConversationItem } from './conversation-item'
import type { ClaudeMessage, ConversationEntry } from '../../types'

interface ConversationListProps {
  logs: string[]
  isStreaming?: boolean
}

function parseLogLine(raw: string, index: number): ConversationEntry {
  const id = `entry-${index}-${raw.slice(0, 20)}`

  try {
    const parsed = JSON.parse(raw) as ClaudeMessage
    return { id, raw, parsed }
  } catch {
    return { id, raw, parsed: null, error: 'Invalid JSON' }
  }
}

export function ConversationList({ logs, isStreaming = false }: ConversationListProps) {
  const entries = useMemo(() => {
    return logs.map((log, index) => parseLogLine(log, index))
  }, [logs])

  if (entries.length === 0) {
    return (
      <div className="flex items-center justify-center h-full text-neutral-500 text-sm">
        No messages yet
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-4 p-4">
      {entries.map((entry, index) => (
        <ConversationItem
          key={entry.id}
          entry={entry}
          isStreaming={isStreaming && index === entries.length - 1}
        />
      ))}
    </div>
  )
}
