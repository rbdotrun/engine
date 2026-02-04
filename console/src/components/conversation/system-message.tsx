import { Terminal } from 'lucide-react'
import type { SystemMessage as SystemMessageType } from '../../types'

interface SystemMessageProps {
  message: SystemMessageType
}

export function SystemMessage({ message }: SystemMessageProps) {
  return (
    <div className="flex items-center gap-2 text-neutral-500 text-xs">
      <Terminal size={12} />
      <span>Session initialized in <code className="bg-neutral-800 px-1 rounded">{message.cwd}</code></span>
    </div>
  )
}
