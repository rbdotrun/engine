import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent, waitFor } from '@testing-library/react'
import { Routes, Route } from 'react-router'
import { ConsoleLayout } from '../../src/layouts/console-layout'
import { SessionPage } from '../../src/pages/session-page'
import { EmptyPage } from '../../src/pages/empty-page'
import { renderWithProviders, mockSessions, createMockCable } from '../test-utils'

const mockCable = createMockCable()

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => mockCable.cable
}))

function LayoutWithRoutes() {
  return (
    <Routes>
      <Route element={<ConsoleLayout />}>
        <Route index element={<EmptyPage />} />
        <Route path="sessions/:sessionId" element={<SessionPage />} />
      </Route>
    </Routes>
  )
}

describe('ConsoleLayout', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    localStorage.clear()
    global.fetch = vi.fn((url: string) => {
      // Match single session with history (e.g., /sessions/1)
      const singleSessionMatch = url.match(/\/sessions\/(\d+)$/)
      if (singleSessionMatch) {
        const sessionId = parseInt(singleSessionMatch[1])
        const session = mockSessions.find(s => s.id === sessionId) || mockSessions[0]
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ ...session, history: [] })
        })
      }
      // Match sessions list
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    }) as unknown as typeof fetch
  })

  describe('header', () => {
    it('displays Claude Code title', async () => {
      renderWithProviders(<LayoutWithRoutes />)

      await waitFor(() => {
        expect(screen.getByText('Claude Code')).toBeInTheDocument()
      })
    })

    it('displays sandbox ID', async () => {
      renderWithProviders(<LayoutWithRoutes />)

      await waitFor(() => {
        expect(screen.getByText(/Sandbox:/)).toBeInTheDocument()
      })
    })

    it('shows disconnected status initially', async () => {
      renderWithProviders(<LayoutWithRoutes />)

      await waitFor(() => {
        // The status indicator should have red background when disconnected
        const statusIndicator = document.querySelector('.bg-red-500')
        expect(statusIndicator).toBeInTheDocument()
      })
    })

    it('shows connected status after connection', async () => {
      renderWithProviders(<LayoutWithRoutes />)

      mockCable.simulateConnect()

      await waitFor(() => {
        // The status indicator should have green background when connected
        const statusIndicator = document.querySelector('.bg-emerald-500')
        expect(statusIndicator).toBeInTheDocument()
      })
    })
  })

  describe('session tabs', () => {
    it('loads and displays sessions', async () => {
      renderWithProviders(<LayoutWithRoutes />)

      await waitFor(() => {
        expect(screen.getByText('My Session')).toBeInTheDocument()
        expect(screen.getByText('Session 2')).toBeInTheDocument()
      })
    })

    it('navigates to session when tab is clicked', async () => {
      renderWithProviders(<LayoutWithRoutes />)

      await waitFor(() => {
        expect(screen.getByText('My Session')).toBeInTheDocument()
      })

      fireEvent.click(screen.getByText('My Session'))

      await waitFor(() => {
        // Should show the session page input
        expect(screen.getByPlaceholderText('Enter a prompt for Claude...')).toBeInTheDocument()
      })
    })

    it('creates new session when + is clicked', async () => {
      const newSession = {
        id: 3,
        sandbox_id: 1,
        session_uuid: 'uuid-3',
        title: null,
        display_name: 'Session 3',
        created_at: '2024-01-03T00:00:00Z',
        updated_at: '2024-01-03T00:00:00Z'
      }

      const fetchMock = vi.fn((url: string, options?: RequestInit) => {
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

      global.fetch = fetchMock

      renderWithProviders(<LayoutWithRoutes />)

      // Wait for initial sessions fetch to complete
      await waitFor(() => {
        expect(screen.getByText('My Session')).toBeInTheDocument()
      })

      // Click the + button
      const addButton = screen.getByTitle('New session')
      fireEvent.click(addButton)

      // Verify POST was called
      await waitFor(() => {
        const postCalls = fetchMock.mock.calls.filter(
          ([, opts]) => opts?.method === 'POST'
        )
        expect(postCalls.length).toBeGreaterThan(0)
      })
    })

    it('highlights active session tab', async () => {
      renderWithProviders(<LayoutWithRoutes />, { initialEntries: ['/sessions/1'] })

      await waitFor(() => {
        const activeTab = screen.getByText('My Session')
        expect(activeTab.className).toContain('bg-emerald-500')
      })
    })
  })

  describe('routing', () => {
    it('shows empty page at root', async () => {
      renderWithProviders(<LayoutWithRoutes />, { initialEntries: ['/'] })

      await waitFor(() => {
        expect(screen.getByText('Click to create a session')).toBeInTheDocument()
      })
    })

    it('shows session page at /sessions/:id', async () => {
      renderWithProviders(<LayoutWithRoutes />, { initialEntries: ['/sessions/1'] })

      await waitFor(() => {
        expect(screen.getByPlaceholderText('Enter a prompt for Claude...')).toBeInTheDocument()
      })
    })

    it('persists session ID to localStorage when navigating', async () => {
      renderWithProviders(<LayoutWithRoutes />)

      await waitFor(() => {
        expect(screen.getByText('My Session')).toBeInTheDocument()
      })

      fireEvent.click(screen.getByText('My Session'))

      await waitFor(() => {
        const stored = localStorage.getItem('rbrun:test-sandbox:ui')
        const parsed = stored ? JSON.parse(stored) : null
        expect(parsed?.sessionId).toBe(1)
      })
    })

    it('stores session in UI state when navigating', async () => {
      renderWithProviders(<LayoutWithRoutes />, { initialEntries: ['/sessions/1'] })

      await waitFor(() => {
        expect(screen.getByPlaceholderText('Enter a prompt for Claude...')).toBeInTheDocument()
      })

      // Verify UI state is persisted
      const stored = localStorage.getItem('rbrun:test-sandbox:ui')
      const parsed = stored ? JSON.parse(stored) : null
      expect(parsed?.sessionId).toBe(1)
    })
  })

  describe('outlet', () => {
    it('renders child routes in main area', async () => {
      renderWithProviders(<LayoutWithRoutes />, { initialEntries: ['/sessions/1'] })

      await waitFor(() => {
        // The outlet should render SessionPage
        expect(screen.getByPlaceholderText('Enter a prompt for Claude...')).toBeInTheDocument()
      })
    })
  })
})
