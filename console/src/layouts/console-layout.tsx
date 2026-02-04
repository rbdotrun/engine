import { Outlet, useNavigate, useParams } from 'react-router'
import { useEffect } from 'react'
import { useConsole } from '../context/console-context'
import { useSessions, useCreateSession, useAddSessionToCache } from '../hooks/use-sessions'
import { SessionTabs } from '../components/session-tabs'

export function ConsoleLayout() {
  const navigate = useNavigate()
  const { sessionId } = useParams()
  const { config, connected, setActiveSessionId } = useConsole()
  const { data: sessions = [], isLoading } = useSessions()
  const createSession = useCreateSession()
  const addSessionToCache = useAddSessionToCache()

  useEffect(() => {
    const id = sessionId ? Number(sessionId) : null
    setActiveSessionId(id)
  }, [sessionId, setActiveSessionId])

  useEffect(() => {
    const handleSessionCreated = (session: { id: number }) => {
      addSessionToCache(session as any)
      navigate(`/sessions/${session.id}`)
    }
    return () => {}
  }, [addSessionToCache, navigate])

  const handleSelectSession = (id: number) => {
    navigate(`/sessions/${id}`)
  }

  const handleCreateSession = async () => {
    try {
      const session = await createSession.mutateAsync()
      navigate(`/sessions/${session.id}`)
    } catch (error) {
      console.error('Failed to create session:', error)
    }
  }

  return (
    <div className="flex flex-col h-full bg-neutral-900 rounded-xl overflow-hidden">
      <header className="flex justify-between items-center px-4 py-3 bg-neutral-800 border-b border-neutral-700">
        <span className="flex items-center gap-2 text-emerald-500 font-semibold text-sm">
          Claude Code
          <span className={`w-2 h-2 rounded-full ${connected ? 'bg-emerald-500' : 'bg-red-500'}`} />
        </span>
        <span className="text-neutral-500 text-xs">Sandbox: {config.sandboxId}</span>
      </header>
      <SessionTabs
        sessions={sessions}
        activeSessionId={sessionId ? Number(sessionId) : null}
        onSelect={handleSelectSession}
        onCreate={handleCreateSession}
        loading={isLoading || createSession.isPending}
      />
      <main className="flex-1 flex flex-col overflow-hidden">
        <Outlet />
      </main>
    </div>
  )
}
