import { Plus } from 'lucide-react'
import { Session } from '../types'

interface SessionTabsProps {
  sessions: Session[]
  activeSessionId: number | null
  onSelect: (sessionId: number) => void
  onCreate: () => void
  loading: boolean
}

export function SessionTabs({ sessions, activeSessionId, onSelect, onCreate, loading }: SessionTabsProps) {
  return (
    <div className="px-3 py-2 bg-neutral-800/50 border-b border-neutral-700">
      <div className="flex gap-1 overflow-x-auto">
        {sessions.map(session => (
          <button
            key={session.id}
            className={`px-3 py-1.5 border rounded-md text-xs whitespace-nowrap transition-all cursor-pointer ${
              session.id === activeSessionId
                ? 'bg-emerald-500 border-emerald-500 text-white'
                : 'bg-neutral-900 border-neutral-700 text-neutral-500 hover:bg-neutral-800 hover:text-neutral-300'
            }`}
            onClick={() => onSelect(session.id)}
          >
            {session.display_name}
          </button>
        ))}
        <button
          className="flex items-center justify-center w-8 h-8 border border-dashed border-neutral-700 rounded-md bg-transparent text-neutral-500 cursor-pointer transition-all hover:border-emerald-500 hover:text-emerald-500 disabled:opacity-50 disabled:cursor-not-allowed"
          onClick={onCreate}
          disabled={loading}
          title="New session"
        >
          <Plus size={14} />
        </button>
      </div>
    </div>
  )
}
