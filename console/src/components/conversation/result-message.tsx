import { CheckCircle, XCircle } from 'lucide-react'
import type { ResultMessage as ResultMessageType } from '../../types'

interface ResultMessageProps {
  message: ResultMessageType
}

export function ResultMessage({ message }: ResultMessageProps) {
  const isSuccess = message.subtype === 'success'
  const isError = message.is_error || message.subtype === 'error' || message.subtype === 'error_during_execution'

  return (
    <div
      className={`flex flex-col gap-1 text-xs px-3 py-2 rounded-lg ${
        isSuccess
          ? 'text-emerald-400 bg-emerald-500/10 border border-emerald-500/30'
          : 'text-red-400 bg-red-500/10 border border-red-500/30'
      }`}
    >
      <div className="flex items-center gap-2">
        {isSuccess ? <CheckCircle size={14} /> : <XCircle size={14} />}
        <span>{isSuccess ? 'Completed successfully' : 'Failed'}</span>
        {message.result && (
          <span className="text-neutral-400">- {message.result}</span>
        )}
      </div>
      {isError && message.errors && message.errors.length > 0 && (
        <div className="mt-1 text-red-300/80 text-xs">
          {message.errors.map((err, i) => (
            <div key={i}>{err}</div>
          ))}
        </div>
      )}
    </div>
  )
}
