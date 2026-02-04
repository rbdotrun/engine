import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Session, SessionWithHistory } from '../types'
import { useConsole } from '../context/console-context'

async function fetchSessions(apiUrl: string, sandboxId: string): Promise<Session[]> {
  const response = await fetch(`${apiUrl}/sandboxes/${sandboxId}/sessions`)
  if (!response.ok) throw new Error('Failed to fetch sessions')
  return response.json()
}

async function createSession(apiUrl: string, sandboxId: string, title?: string): Promise<Session> {
  const response = await fetch(`${apiUrl}/sandboxes/${sandboxId}/sessions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title })
  })
  if (!response.ok) throw new Error('Failed to create session')
  return response.json()
}

export async function fetchSessionHistory(apiUrl: string, sandboxId: string, sessionId: number): Promise<SessionWithHistory> {
  const response = await fetch(`${apiUrl}/sandboxes/${sandboxId}/sessions/${sessionId}`)
  if (!response.ok) throw new Error('Failed to fetch session history')
  return response.json()
}

export function useSessions() {
  const { config } = useConsole()
  const { apiUrl, sandboxId } = config

  return useQuery({
    queryKey: ['sessions', sandboxId],
    queryFn: () => fetchSessions(apiUrl, sandboxId)
  })
}

export function useCreateSession() {
  const queryClient = useQueryClient()
  const { config, setActiveSessionId } = useConsole()
  const { apiUrl, sandboxId } = config

  return useMutation({
    mutationFn: (title?: string) => createSession(apiUrl, sandboxId, title),
    onSuccess: (session) => {
      queryClient.setQueryData<Session[]>(['sessions', sandboxId], (old) => {
        if (!old) return [session]
        return [session, ...old]
      })
      setActiveSessionId(session.id)
    }
  })
}

export function useAddSessionToCache() {
  const queryClient = useQueryClient()
  const { config } = useConsole()
  const { sandboxId } = config

  return (session: Session) => {
    queryClient.setQueryData<Session[]>(['sessions', sandboxId], (old) => {
      if (!old) return [session]
      if (old.some(s => s.id === session.id)) return old
      return [session, ...old]
    })
  }
}

export function useSessionHistory(sessionId: number | null) {
  const { config } = useConsole()
  const { apiUrl, sandboxId } = config

  return useQuery({
    queryKey: ['session-history', sandboxId, sessionId],
    queryFn: () => fetchSessionHistory(apiUrl, sandboxId, sessionId!),
    enabled: sessionId !== null
  })
}
