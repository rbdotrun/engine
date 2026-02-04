import { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react'
import { createConsumer, Subscription } from '@rails/actioncable'
import { Config, Session, OutputLine } from '../types'
import { ConsoleState, UIState, loadUIState, saveUIState } from './ui-state'

export type { ConsoleState } from './ui-state'

interface ConsoleContextValue {
  config: Config
  connected: boolean
  // Persisted UI state
  consoleState: ConsoleState
  setConsoleState: (state: ConsoleState) => void
  activeSessionId: number | null
  setActiveSessionId: (id: number | null) => void
  diffOpen: boolean
  setDiffOpen: (open: boolean) => void
  // Runtime state
  outputBySession: Record<number, OutputLine[]>
  runClaude: (prompt: string, sessionId: number) => void
  appendOutput: (sessionId: number, text: string) => void
  onSessionCreated: (session: Session) => void
}

const ConsoleContext = createContext<ConsoleContextValue | null>(null)

export function useConsole() {
  const context = useContext(ConsoleContext)
  if (!context) throw new Error('useConsole must be used within ConsoleProvider')
  return context
}

interface ConsoleProviderProps {
  config: Config
  children: ReactNode
  onSessionCreated?: (session: Session) => void
}

export function ConsoleProvider({ config, children, onSessionCreated: externalOnSessionCreated }: ConsoleProviderProps) {
  // Load initial state from localStorage
  const [uiState, setUIState] = useState<UIState>(() => loadUIState(config.sandboxId))

  const [connected, setConnected] = useState(false)
  const [outputBySession, setOutputBySession] = useState<Record<number, OutputLine[]>>({})
  const [channel, setChannel] = useState<Subscription | null>(null)

  // Persist state changes to localStorage
  useEffect(() => {
    saveUIState(config.sandboxId, uiState)
  }, [config.sandboxId, uiState])

  const setConsoleState = useCallback((consoleState: ConsoleState) => {
    setUIState(prev => ({ ...prev, consoleState }))
  }, [])

  const setActiveSessionId = useCallback((sessionId: number | null) => {
    setUIState(prev => ({ ...prev, sessionId }))
  }, [])

  const setDiffOpen = useCallback((diffOpen: boolean) => {
    setUIState(prev => ({ ...prev, diffOpen }))
  }, [])

  const appendOutput = useCallback((sessionId: number, text: string) => {
    const line: OutputLine = {
      id: `${sessionId}-${Date.now()}-${Math.random().toString(36).slice(2)}`,
      text,
      timestamp: Date.now()
    }
    setOutputBySession(prev => ({
      ...prev,
      [sessionId]: [...(prev[sessionId] || []), line]
    }))
  }, [])

  const onSessionCreated = useCallback((session: Session) => {
    externalOnSessionCreated?.(session)
    setActiveSessionId(session.id)
  }, [externalOnSessionCreated, setActiveSessionId])

  useEffect(() => {
    const cable = createConsumer(`${config.wsUrl}?token=${config.token}`)

    const subscription = cable.subscriptions.create(
      { channel: 'Rbrun::SandboxChannel', token: config.token, sandbox_id: config.sandboxId },
      {
        connected() {
          console.log('ActionCable: connected')
          setConnected(true)
        },
        disconnected() {
          console.log('ActionCable: disconnected')
          setConnected(false)
        },
        rejected() {
          console.error('ActionCable: subscription REJECTED')
        },
        received(data: {
          type: string
          line?: string
          success?: boolean
          message?: string
          session_id?: number | null
          session?: Session
        }) {
          const sessionId = data.session_id
          if (data.type === 'output' && data.line && sessionId) {
            appendOutput(sessionId, data.line)
          }
          if (data.type === 'error' && data.message && sessionId) {
            const errorJson = JSON.stringify({
              type: 'result',
              subtype: 'error',
              errors: [data.message]
            })
            appendOutput(sessionId, errorJson)
          }
          if (data.type === 'session_created' && data.session) {
            onSessionCreated(data.session)
          }
        }
      }
    )

    setChannel(subscription)
    return () => cable.disconnect()
  }, [config.wsUrl, config.token, config.sandboxId, appendOutput, onSessionCreated])

  const runClaude = useCallback((prompt: string, sessionId: number) => {
    if (!channel) {
      appendOutput(sessionId, JSON.stringify({ type: 'result', subtype: 'error', errors: ['Not connected'] }))
      return
    }
    channel.perform('run_claude', { prompt, session_id: sessionId })
  }, [channel, appendOutput])

  return (
    <ConsoleContext.Provider value={{
      config,
      connected,
      consoleState: uiState.consoleState,
      setConsoleState,
      activeSessionId: uiState.sessionId,
      setActiveSessionId,
      diffOpen: uiState.diffOpen,
      setDiffOpen,
      outputBySession,
      runClaude,
      appendOutput,
      onSessionCreated
    }}>
      {children}
    </ConsoleContext.Provider>
  )
}
