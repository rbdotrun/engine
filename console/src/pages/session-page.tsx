import { useParams } from 'react-router'
import { useState, useRef, useEffect, useMemo } from 'react'
import { Send, GitBranch } from 'lucide-react'
import { useConsole } from '../context/console-context'
import { useSessionHistory } from '../hooks/use-sessions'
import { ConversationList } from '../components/conversation'
import { DiffViewer } from '../components/diff-viewer'

export function SessionPage() {
  const { sessionId } = useParams()
  const { outputBySession, runClaude, diffOpen, setDiffOpen } = useConsole()
  const [input, setInput] = useState('')
  const outputRef = useRef<HTMLDivElement>(null)

  const numericSessionId = sessionId ? Number(sessionId) : null
  const { data: sessionWithHistory, isLoading } = useSessionHistory(numericSessionId)

  // Merge history logs (from API) with live output lines (from WebSocket)
  const logs = useMemo(() => {
    const historyLogs = sessionWithHistory?.history?.flatMap(exec => exec.logs) ?? []
    const liveLogs = numericSessionId
      ? (outputBySession[numericSessionId] || []).map(line => line.text)
      : []
    return [...historyLogs, ...liveLogs]
  }, [sessionWithHistory, numericSessionId, outputBySession])

  const isStreaming = useMemo(() => {
    const liveLines = numericSessionId ? (outputBySession[numericSessionId] || []) : []
    return liveLines.length > 0
  }, [numericSessionId, outputBySession])

  useEffect(() => {
    if (outputRef.current) {
      outputRef.current.scrollTop = outputRef.current.scrollHeight
    }
  }, [logs])

  const handleSubmit = () => {
    if (input.trim() && sessionId) {
      runClaude(input.trim(), Number(sessionId))
      setInput('')
    }
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="flex-1 overflow-y-auto" ref={outputRef}>
        {isLoading ? (
          <div className="flex items-center justify-center h-full text-neutral-500 text-sm">
            Loading...
          </div>
        ) : (
          <ConversationList logs={logs} isStreaming={isStreaming} />
        )}
      </div>
      <div className="p-3 bg-neutral-800 border-t border-neutral-700">
        <div className="flex gap-2">
          <input
            className="flex-1 px-3 py-2.5 border border-neutral-700 rounded-lg bg-neutral-900 text-white text-sm outline-none focus:border-emerald-500 placeholder:text-neutral-500"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleSubmit()}
            placeholder="Enter a prompt for Claude..."
          />
          {sessionWithHistory?.git_diff && (
            <button
              className="px-3 py-2.5 bg-neutral-700 text-neutral-300 border-none rounded-lg cursor-pointer hover:bg-neutral-600 hover:text-white transition-colors"
              onClick={() => setDiffOpen(true)}
              title="View changes"
            >
              <GitBranch size={16} />
            </button>
          )}
          <button
            className="px-3 py-2.5 bg-emerald-500 text-white border-none rounded-lg cursor-pointer hover:bg-emerald-600 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            onClick={handleSubmit}
            disabled={!input.trim()}
          >
            <Send size={16} />
          </button>
        </div>
      </div>

      {diffOpen && sessionWithHistory?.git_diff && (
        <DiffViewer
          diff={sessionWithHistory.git_diff}
          onClose={() => setDiffOpen(false)}
        />
      )}
    </div>
  )
}
