import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useSessions, useCreateSession, useAddSessionToCache, useSessionHistory } from '../../src/hooks/use-sessions'
import { ConsoleProvider } from '../../src/context/console-context'
import { mockConfig, mockSessions, createMockCable } from '../test-utils'

const mockCable = createMockCable()

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => mockCable.cable
}))

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },
      mutations: { retry: false }
    }
  })

  return function Wrapper({ children }: { children: ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        <ConsoleProvider config={mockConfig}>
          {children}
        </ConsoleProvider>
      </QueryClientProvider>
    )
  }
}

describe('useSessions', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('fetches sessions on mount', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    ) as unknown as typeof fetch

    const { result } = renderHook(() => useSessions(), { wrapper: createWrapper() })

    await waitFor(() => {
      expect(result.current.isSuccess).toBe(true)
    })

    expect(result.current.data).toEqual(mockSessions)
    expect(fetch).toHaveBeenCalledWith(
      `${mockConfig.apiUrl}/sandboxes/${mockConfig.sandboxId}/sessions`
    )
  })

  it('returns loading state while fetching', () => {
    global.fetch = vi.fn(() => new Promise(() => {})) as unknown as typeof fetch

    const { result } = renderHook(() => useSessions(), { wrapper: createWrapper() })

    expect(result.current.isLoading).toBe(true)
    expect(result.current.data).toBeUndefined()
  })

  it('handles fetch error', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: false,
        status: 500
      })
    ) as unknown as typeof fetch

    const { result } = renderHook(() => useSessions(), { wrapper: createWrapper() })

    await waitFor(() => {
      expect(result.current.isError).toBe(true)
    })
  })

  it('returns empty array when no sessions', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve([])
      })
    ) as unknown as typeof fetch

    const { result } = renderHook(() => useSessions(), { wrapper: createWrapper() })

    await waitFor(() => {
      expect(result.current.isSuccess).toBe(true)
    })

    expect(result.current.data).toEqual([])
  })
})

describe('useCreateSession', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('creates session via POST request', async () => {
    const newSession = {
      id: 3,
      sandbox_id: 1,
      session_uuid: 'uuid-3',
      title: null,
      display_name: 'Session 3',
      created_at: '2024-01-03T00:00:00Z',
      updated_at: '2024-01-03T00:00:00Z'
    }

    global.fetch = vi.fn((url, options) => {
      if (options?.method === 'POST') {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve(newSession)
        })
      }
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    }) as unknown as typeof fetch

    const { result } = renderHook(() => useCreateSession(), { wrapper: createWrapper() })

    const session = await result.current.mutateAsync()

    expect(session).toEqual(newSession)
    expect(fetch).toHaveBeenCalledWith(
      `${mockConfig.apiUrl}/sandboxes/${mockConfig.sandboxId}/sessions`,
      expect.objectContaining({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' }
      })
    )
  })

  it('sends title in request body when provided', async () => {
    global.fetch = vi.fn((url, options) => {
      if (options?.method === 'POST') {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ ...mockSessions[0], title: 'Custom Title' })
        })
      }
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    }) as unknown as typeof fetch

    const { result } = renderHook(() => useCreateSession(), { wrapper: createWrapper() })

    await result.current.mutateAsync('Custom Title')

    expect(fetch).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        body: JSON.stringify({ title: 'Custom Title' })
      })
    )
  })

  it('handles create error', async () => {
    global.fetch = vi.fn((url, options) => {
      if (options?.method === 'POST') {
        return Promise.resolve({
          ok: false,
          status: 500
        })
      }
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    }) as unknown as typeof fetch

    const { result } = renderHook(() => useCreateSession(), { wrapper: createWrapper() })

    await expect(result.current.mutateAsync()).rejects.toThrow('Failed to create session')
  })

  it('updates cache with new session on success', async () => {
    const newSession = {
      id: 3,
      sandbox_id: 1,
      session_uuid: 'uuid-3',
      title: null,
      display_name: 'Session 3',
      created_at: '2024-01-03T00:00:00Z',
      updated_at: '2024-01-03T00:00:00Z'
    }

    global.fetch = vi.fn((url, options) => {
      if (options?.method === 'POST') {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve(newSession)
        })
      }
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    }) as unknown as typeof fetch

    const queryClient = new QueryClient({
      defaultOptions: {
        queries: { retry: false, gcTime: 0 },
        mutations: { retry: false }
      }
    })

    function Wrapper({ children }: { children: ReactNode }) {
      return (
        <QueryClientProvider client={queryClient}>
          <ConsoleProvider config={mockConfig}>
            {children}
          </ConsoleProvider>
        </QueryClientProvider>
      )
    }

    // First fetch sessions
    const { result: sessionsResult } = renderHook(() => useSessions(), { wrapper: Wrapper })
    await waitFor(() => expect(sessionsResult.current.isSuccess).toBe(true))

    // Then create new session
    const { result: createResult } = renderHook(() => useCreateSession(), { wrapper: Wrapper })
    await createResult.current.mutateAsync()

    // Check cache was updated
    const cachedData = queryClient.getQueryData(['sessions', mockConfig.sandboxId])
    expect(cachedData).toContainEqual(newSession)
  })
})

describe('useAddSessionToCache', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('adds session to cache', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    ) as unknown as typeof fetch

    const queryClient = new QueryClient({
      defaultOptions: {
        queries: { retry: false, gcTime: 0 },
        mutations: { retry: false }
      }
    })

    function Wrapper({ children }: { children: ReactNode }) {
      return (
        <QueryClientProvider client={queryClient}>
          <ConsoleProvider config={mockConfig}>
            {children}
          </ConsoleProvider>
        </QueryClientProvider>
      )
    }

    // First fetch sessions
    const { result: sessionsResult } = renderHook(() => useSessions(), { wrapper: Wrapper })
    await waitFor(() => expect(sessionsResult.current.isSuccess).toBe(true))

    // Add session to cache
    const { result: addResult } = renderHook(() => useAddSessionToCache(), { wrapper: Wrapper })
    const newSession = {
      id: 99,
      sandbox_id: 1,
      session_uuid: 'uuid-99',
      title: 'Added Session',
      display_name: 'Added Session',
      created_at: '2024-01-01T00:00:00Z',
      updated_at: '2024-01-01T00:00:00Z'
    }

    addResult.current(newSession)

    const cachedData = queryClient.getQueryData(['sessions', mockConfig.sandboxId])
    expect(cachedData).toContainEqual(newSession)
  })

  it('does not duplicate existing session', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    ) as unknown as typeof fetch

    const queryClient = new QueryClient({
      defaultOptions: {
        queries: { retry: false, gcTime: 0 },
        mutations: { retry: false }
      }
    })

    function Wrapper({ children }: { children: ReactNode }) {
      return (
        <QueryClientProvider client={queryClient}>
          <ConsoleProvider config={mockConfig}>
            {children}
          </ConsoleProvider>
        </QueryClientProvider>
      )
    }

    // First fetch sessions
    const { result: sessionsResult } = renderHook(() => useSessions(), { wrapper: Wrapper })
    await waitFor(() => expect(sessionsResult.current.isSuccess).toBe(true))

    // Try to add existing session
    const { result: addResult } = renderHook(() => useAddSessionToCache(), { wrapper: Wrapper })
    addResult.current(mockSessions[0])

    const cachedData = queryClient.getQueryData(['sessions', mockConfig.sandboxId]) as typeof mockSessions
    const count = cachedData.filter(s => s.id === mockSessions[0].id).length
    expect(count).toBe(1)
  })
})

// Mock session history data - validated via Rails runner
const mockSessionWithHistory = {
  id: 1,
  sandbox_id: 1,
  session_uuid: 'uuid-1',
  title: 'Test Session',
  display_name: 'Test Session',
  created_at: '2024-01-01T00:00:00Z',
  updated_at: '2024-01-01T00:00:00Z',
  history: [
    {
      id: 1,
      exit_code: 0,
      logs: [
        '{"type":"system","subtype":"init","cwd":"/home/user"}',
        '{"type":"assistant","message":{"content":[{"type":"text","text":"Hello!"}]}}',
        '{"type":"result","subtype":"success"}'
      ]
    }
  ]
}

describe('useSessionHistory', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('fetches session with history', async () => {
    global.fetch = vi.fn((url) => {
      if (url.includes('/sessions/1')) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve(mockSessionWithHistory)
        })
      }
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    }) as unknown as typeof fetch

    const { result } = renderHook(() => useSessionHistory(1), { wrapper: createWrapper() })

    await waitFor(() => {
      expect(result.current.isSuccess).toBe(true)
    })

    expect(result.current.data).toEqual(mockSessionWithHistory)
    expect(fetch).toHaveBeenCalledWith(
      `${mockConfig.apiUrl}/sandboxes/${mockConfig.sandboxId}/sessions/1`
    )
  })

  it('returns history array with logs', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessionWithHistory)
      })
    ) as unknown as typeof fetch

    const { result } = renderHook(() => useSessionHistory(1), { wrapper: createWrapper() })

    await waitFor(() => {
      expect(result.current.isSuccess).toBe(true)
    })

    expect(result.current.data?.history).toHaveLength(1)
    expect(result.current.data?.history[0].logs).toHaveLength(3)
    expect(result.current.data?.history[0].exit_code).toBe(0)
  })

  it('does not fetch when sessionId is null', () => {
    global.fetch = vi.fn() as unknown as typeof fetch

    renderHook(() => useSessionHistory(null), { wrapper: createWrapper() })

    expect(fetch).not.toHaveBeenCalled()
  })
})
