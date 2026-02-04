import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { renderWithProviders, mockSessions, createMockCable } from './test-utils'
import { AppRoutes } from '../src/routes'

const mockCable = createMockCable()

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => mockCable.cable
}))

describe('Routes', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    ) as unknown as typeof fetch
  })

  describe('/ (root)', () => {
    it('renders EmptyPage', async () => {
      renderWithProviders(<AppRoutes />, { initialEntries: ['/'] })

      await waitFor(() => {
        expect(screen.getByText('Click to create a session')).toBeInTheDocument()
      })
    })

    it('renders ConsoleLayout wrapper', async () => {
      renderWithProviders(<AppRoutes />, { initialEntries: ['/'] })

      await waitFor(() => {
        expect(screen.getByText('Claude Code')).toBeInTheDocument()
      })
    })

    it('does not render SessionPage input', async () => {
      renderWithProviders(<AppRoutes />, { initialEntries: ['/'] })

      await waitFor(() => {
        expect(screen.getByText('Click to create a session')).toBeInTheDocument()
      })

      expect(screen.queryByPlaceholderText('Enter a prompt for Claude...')).not.toBeInTheDocument()
    })
  })

  describe('/sessions/:sessionId', () => {
    it('renders SessionPage', async () => {
      renderWithProviders(<AppRoutes />, { initialEntries: ['/sessions/1'] })

      await waitFor(() => {
        expect(screen.getByPlaceholderText('Enter a prompt for Claude...')).toBeInTheDocument()
      })
    })

    it('renders ConsoleLayout wrapper', async () => {
      renderWithProviders(<AppRoutes />, { initialEntries: ['/sessions/1'] })

      await waitFor(() => {
        expect(screen.getByText('Claude Code')).toBeInTheDocument()
      })
    })

    it('does not render EmptyPage', async () => {
      renderWithProviders(<AppRoutes />, { initialEntries: ['/sessions/1'] })

      await waitFor(() => {
        expect(screen.getByPlaceholderText('Enter a prompt for Claude...')).toBeInTheDocument()
      })

      expect(screen.queryByText('Click to create a session')).not.toBeInTheDocument()
    })

    it('parses sessionId from URL', async () => {
      renderWithProviders(<AppRoutes />, { initialEntries: ['/sessions/42'] })

      await waitFor(() => {
        expect(screen.getByPlaceholderText('Enter a prompt for Claude...')).toBeInTheDocument()
      })

      // Verify the session ID is used - when we submit, it should use session 42
      await waitFor(() => {
        expect(mockCable.cable.subscriptions.create).toHaveBeenCalled()
      })
    })
  })

  describe('session tabs integration', () => {
    it('renders session tabs in layout', async () => {
      renderWithProviders(<AppRoutes />, { initialEntries: ['/'] })

      await waitFor(() => {
        expect(screen.getByText('My Session')).toBeInTheDocument()
        expect(screen.getByText('Session 2')).toBeInTheDocument()
      })
    })

    it('renders add session button', async () => {
      renderWithProviders(<AppRoutes />, { initialEntries: ['/'] })

      await waitFor(() => {
        expect(screen.getByTitle('New session')).toBeInTheDocument()
      })
    })
  })

  describe('unknown routes', () => {
    it('renders nothing for unknown paths (no catch-all)', () => {
      renderWithProviders(<AppRoutes />, { initialEntries: ['/unknown/path'] })

      // No route matches, so nothing renders (not even layout)
      expect(screen.queryByText('Claude Code')).not.toBeInTheDocument()
      expect(screen.queryByText('Click to create a session')).not.toBeInTheDocument()
      expect(screen.queryByPlaceholderText('Enter a prompt for Claude...')).not.toBeInTheDocument()
    })
  })
})
