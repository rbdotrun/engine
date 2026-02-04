import { User } from 'lucide-react'
import type { UserMessage as UserMessageType } from '../../types'

interface UserMessageProps {
  message: UserMessageType
}

export function UserMessage({ message }: UserMessageProps) {
  return (
    <div className="flex items-start gap-3">
      <div className="flex-shrink-0 w-6 h-6 rounded-full bg-neutral-700 flex items-center justify-center">
        <User size={14} className="text-neutral-400" />
      </div>
      <div className="flex-1 text-sm text-neutral-200 pt-0.5">
        {message.text}
      </div>
    </div>
  )
}
