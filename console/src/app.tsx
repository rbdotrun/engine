import { useMemo, useEffect, useCallback } from 'react'
import { MemoryRouter } from 'react-router'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Layers, X, Maximize2, Minimize2 } from 'lucide-react'
import { ConsoleProvider, useConsole } from './context/console-context'
import { AppRoutes } from './routes'
import { Config } from './types'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60,
      retry: 1
    }
  }
})

function getInitialRoute(sandboxId: string): string {
  try {
    const raw = localStorage.getItem(`rbrun:${sandboxId}:ui`)
    if (raw) {
      const parsed = JSON.parse(raw)
      if (parsed.sessionId) return `/sessions/${parsed.sessionId}`
    }
  } catch {}
  return '/'
}

function ConsoleUI() {
  const { consoleState, setConsoleState, diffOpen, setDiffOpen } = useConsole()

  const isOpen = consoleState !== 'closed'
  const isFullscreen = consoleState === 'fullscreen'

  const toggleOpen = () => {
    setConsoleState(consoleState === 'closed' ? 'opened' : 'closed')
  }

  const toggleFullscreen = () => {
    setConsoleState(consoleState === 'fullscreen' ? 'opened' : 'fullscreen')
  }

  // Progressive escape: diff → fullscreen→opened → closed
  const handleEscape = useCallback(() => {
    if (diffOpen) {
      setDiffOpen(false)
    } else if (isFullscreen) {
      setConsoleState('opened')
    } else if (isOpen) {
      setConsoleState('closed')
    }
  }, [diffOpen, setDiffOpen, isFullscreen, isOpen, setConsoleState])

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        e.preventDefault()
        handleEscape()
      }
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, handleEscape])

  return (
    <div className={`fixed z-[9999] font-sans ${isFullscreen ? 'inset-5' : 'bottom-5 right-5'}`}>
      {isOpen && (
        <div className={`bg-neutral-900 rounded-xl shadow-2xl overflow-hidden ${
          isFullscreen
            ? 'w-full h-full'
            : 'absolute bottom-12 right-0 w-[420px] h-[500px]'
        }`}>
          <div className="relative w-full h-full flex flex-col">
            <div className="absolute top-2 right-3 z-10 flex items-center gap-1">
              <button
                className="bg-transparent border-none text-neutral-500 hover:text-white cursor-pointer p-1"
                onClick={toggleFullscreen}
                title={isFullscreen ? 'Minimize' : 'Fullscreen'}
              >
                {isFullscreen ? <Minimize2 size={16} /> : <Maximize2 size={16} />}
              </button>
              <button
                className="bg-transparent border-none text-neutral-500 hover:text-white cursor-pointer p-1"
                onClick={() => setConsoleState('closed')}
              >
                <X size={18} />
              </button>
            </div>
            <AppRoutes />
          </div>
        </div>
      )}
      {!isFullscreen && (
        <button
          className="flex items-center gap-2 px-4 py-2.5 bg-emerald-500 text-white border-none rounded-lg text-sm font-medium cursor-pointer shadow-lg shadow-emerald-500/30 hover:-translate-y-0.5 hover:shadow-xl hover:shadow-emerald-500/40 transition-all"
          onClick={toggleOpen}
        >
          <Layers size={16} />
          rbrun
        </button>
      )}
    </div>
  )
}

export function App({ config }: { config: Config }) {
  const initialRoute = useMemo(() => getInitialRoute(config.sandboxId), [config.sandboxId])

  return (
    <QueryClientProvider client={queryClient}>
      <ConsoleProvider config={config}>
        <MemoryRouter initialEntries={[initialRoute]}>
          <ConsoleUI />
        </MemoryRouter>
      </ConsoleProvider>
    </QueryClientProvider>
  )
}
