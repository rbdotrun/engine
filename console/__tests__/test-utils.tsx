import { ReactNode } from 'react'
import { render, RenderOptions } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { ConsoleProvider } from '../src/context/console-context'
import { Config } from '../src/types'

export const mockConfig: Config = {
  sandboxId: 'test-sandbox',
  wsUrl: 'ws://test.example.com/cable',
  apiUrl: 'http://test.example.com/api',
  token: 'test-token-123'
}

export function createTestQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
        gcTime: 0
      },
      mutations: {
        retry: false
      }
    }
  })
}

interface WrapperProps {
  children: ReactNode
  config?: Config
  initialEntries?: string[]
  queryClient?: QueryClient
}

export function TestProviders({
  children,
  config = mockConfig,
  initialEntries = ['/'],
  queryClient = createTestQueryClient()
}: WrapperProps) {
  return (
    <QueryClientProvider client={queryClient}>
      <ConsoleProvider config={config}>
        <MemoryRouter initialEntries={initialEntries}>
          {children}
        </MemoryRouter>
      </ConsoleProvider>
    </QueryClientProvider>
  )
}

export function renderWithProviders(
  ui: ReactNode,
  options?: Omit<RenderOptions, 'wrapper'> & {
    config?: Config
    initialEntries?: string[]
    queryClient?: QueryClient
  }
) {
  const { config, initialEntries, queryClient, ...renderOptions } = options || {}

  return render(ui, {
    wrapper: ({ children }) => (
      <TestProviders
        config={config}
        initialEntries={initialEntries}
        queryClient={queryClient}
      >
        {children}
      </TestProviders>
    ),
    ...renderOptions
  })
}

// Mock session data
export const mockSessions = [
  {
    id: 1,
    sandbox_id: 1,
    session_uuid: 'uuid-1',
    title: 'My Session',
    display_name: 'My Session',
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z'
  },
  {
    id: 2,
    sandbox_id: 1,
    session_uuid: 'uuid-2',
    title: null,
    display_name: 'Session 2',
    created_at: '2024-01-02T00:00:00Z',
    updated_at: '2024-01-02T00:00:00Z'
  }
]

// Mock fetch responses
export function mockFetch(responses: Record<string, unknown>) {
  return vi.fn((url: string, options?: RequestInit) => {
    const method = options?.method || 'GET'
    const key = `${method} ${url}`

    for (const [pattern, response] of Object.entries(responses)) {
      if (key.includes(pattern) || url.includes(pattern)) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve(response)
        })
      }
    }

    return Promise.resolve({
      ok: false,
      status: 404,
      json: () => Promise.resolve({ error: 'Not found' })
    })
  })
}

// ActionCable mock utilities
export type MessageHandler = (data: unknown) => void

export function createMockCable() {
  let messageHandler: MessageHandler | null = null
  let connectedHandler: (() => void) | null = null
  let disconnectedHandler: (() => void) | null = null

  const subscription = {
    perform: vi.fn(),
    unsubscribe: vi.fn()
  }

  const cable = {
    subscriptions: {
      create: vi.fn((_channel: unknown, handlers: {
        connected?: () => void
        disconnected?: () => void
        received?: MessageHandler
      }) => {
        connectedHandler = handlers.connected || null
        disconnectedHandler = handlers.disconnected || null
        messageHandler = handlers.received || null
        // Auto-connect after subscription is created
        setTimeout(() => connectedHandler?.(), 0)
        return subscription
      })
    },
    disconnect: vi.fn()
  }

  return {
    cable,
    subscription,
    simulateConnect: () => connectedHandler?.(),
    simulateDisconnect: () => disconnectedHandler?.(),
    simulateMessage: (data: unknown) => messageHandler?.(data),
    getMessageHandler: () => messageHandler,
    isSubscribed: () => messageHandler !== null
  }
}
