import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Routes, Route } from 'react-router'
import { SessionPage } from '../../src/pages/session-page'
import { renderWithProviders, createMockCable } from '../test-utils'

const mockCable = createMockCable()

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => mockCable.cable
}))

// Mock fetch to return empty history for session API calls
const mockFetch = vi.fn((url: string) => {
  if (url.includes('/sessions/')) {
    return Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        id: 1,
        sandbox_id: 1,
        session_uuid: 'test-uuid',
        title: null,
        display_name: 'Session 1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        history: []
      })
    })
  }
  return Promise.resolve({ ok: false, status: 404 })
})

function SessionPageWithRoute() {
  return (
    <Routes>
      <Route path="/sessions/:sessionId" element={<SessionPage />} />
    </Routes>
  )
}

describe('SessionPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.stubGlobal('fetch', mockFetch)
    mockCable.simulateConnect()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  describe('rendering', () => {
    it('renders input field', () => {
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      expect(screen.getByPlaceholderText('Enter a prompt for Claude...')).toBeInTheDocument()
    })

    it('renders send button', () => {
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const buttons = screen.getAllByRole('button')
      expect(buttons.length).toBeGreaterThan(0)
    })

    it('renders loading state then empty message state', async () => {
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      // Initially shows loading
      expect(screen.getByText('Loading...')).toBeInTheDocument()

      // After fetch completes, shows no messages
      await waitFor(() => {
        expect(screen.getByText('No messages yet')).toBeInTheDocument()
      })
    })
  })

  describe('input handling', () => {
    it('updates input value when typing', async () => {
      const user = userEvent.setup()
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const input = screen.getByPlaceholderText('Enter a prompt for Claude...')
      await user.type(input, 'Hello Claude')

      expect(input).toHaveValue('Hello Claude')
    })

    it('clears input after submission', async () => {
      const user = userEvent.setup()
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const input = screen.getByPlaceholderText('Enter a prompt for Claude...')
      await user.type(input, 'Hello Claude')
      await user.keyboard('{Enter}')

      expect(input).toHaveValue('')
    })

    it('does not submit empty input', async () => {
      const user = userEvent.setup()
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const input = screen.getByPlaceholderText('Enter a prompt for Claude...')
      await user.keyboard('{Enter}')

      expect(mockCable.subscription.perform).not.toHaveBeenCalled()
    })

    it('does not submit whitespace-only input', async () => {
      const user = userEvent.setup()
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const input = screen.getByPlaceholderText('Enter a prompt for Claude...')
      await user.type(input, '   ')
      await user.keyboard('{Enter}')

      expect(mockCable.subscription.perform).not.toHaveBeenCalled()
    })
  })

  describe('prompt submission', () => {
    it('sends prompt via ActionCable on Enter key', async () => {
      const user = userEvent.setup()
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const input = screen.getByPlaceholderText('Enter a prompt for Claude...')
      await user.type(input, 'Hello Claude')
      await user.keyboard('{Enter}')

      expect(mockCable.subscription.perform).toHaveBeenCalledWith('run_claude', {
        prompt: 'Hello Claude',
        session_id: 1
      })
    })

    it('sends prompt via ActionCable on button click', async () => {
      const user = userEvent.setup()
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const input = screen.getByPlaceholderText('Enter a prompt for Claude...')
      await user.type(input, 'Hello Claude')

      // Find the send button (it's the one that's not disabled)
      const buttons = screen.getAllByRole('button')
      const sendButton = buttons[0]
      await user.click(sendButton)

      expect(mockCable.subscription.perform).toHaveBeenCalledWith('run_claude', {
        prompt: 'Hello Claude',
        session_id: 1
      })
    })

    it('sends prompt and waits for backend broadcast', async () => {
      const user = userEvent.setup()
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const input = screen.getByPlaceholderText('Enter a prompt for Claude...')
      await user.type(input, 'Hello Claude')
      await user.keyboard('{Enter}')

      // Prompt is NOT added optimistically - it comes from backend
      // Simulate backend broadcasting the saved user message
      mockCable.simulateMessage({
        type: 'output',
        line: '{"type":"user","text":"Hello Claude"}',
        session_id: 1
      })

      await waitFor(() => {
        expect(screen.getByText('Hello Claude')).toBeInTheDocument()
      })
    })
  })

  describe('output display', () => {
    it('displays output lines from ActionCable messages', async () => {
      const user = userEvent.setup()
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const input = screen.getByPlaceholderText('Enter a prompt for Claude...')
      await user.type(input, 'Hello')
      await user.keyboard('{Enter}')

      // Simulate output from server
      mockCable.simulateMessage({
        type: 'output',
        line: 'Hello! How can I help?',
        session_id: 1
      })

      await waitFor(() => {
        expect(screen.getByText('Hello! How can I help?')).toBeInTheDocument()
      })
    })

    it('ignores complete broadcast (result comes from Claude output)', async () => {
      const user = userEvent.setup()
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const input = screen.getByPlaceholderText('Enter a prompt for Claude...')
      await user.type(input, 'Hello')
      await user.keyboard('{Enter}')

      // Complete is just a status signal, not added to output
      mockCable.simulateMessage({
        type: 'complete',
        success: true,
        session_id: 1
      })

      // Should not find [Done] since we no longer add it
      expect(screen.queryByText('[Done]')).not.toBeInTheDocument()
    })

    it('displays result message from Claude output', async () => {
      const user = userEvent.setup()
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const input = screen.getByPlaceholderText('Enter a prompt for Claude...')
      await user.type(input, 'Hello')
      await user.keyboard('{Enter}')

      // Result comes as JSON from Claude CLI output
      mockCable.simulateMessage({
        type: 'output',
        line: '{"type":"result","subtype":"success"}',
        session_id: 1
      })

      await waitFor(() => {
        expect(screen.getByText('Completed successfully')).toBeInTheDocument()
      })
    })

    it('displays error messages as result with errors', async () => {
      const user = userEvent.setup()
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      const input = screen.getByPlaceholderText('Enter a prompt for Claude...')
      await user.type(input, 'Hello')
      await user.keyboard('{Enter}')

      // Backend error gets converted to JSON result message
      mockCable.simulateMessage({
        type: 'error',
        message: 'Connection failed',
        session_id: 1
      })

      await waitFor(() => {
        expect(screen.getByText('Connection failed')).toBeInTheDocument()
      })
    })

    it('only displays output for current session', async () => {
      renderWithProviders(<SessionPageWithRoute />, { initialEntries: ['/sessions/1'] })

      // Wait for subscription to be created
      await waitFor(() => {
        expect(mockCable.cable.subscriptions.create).toHaveBeenCalled()
      })

      // Message for current session (should appear)
      mockCable.simulateMessage({
        type: 'output',
        line: 'Session 1 output',
        session_id: 1
      })

      // Message for different session (stored but not displayed here)
      mockCable.simulateMessage({
        type: 'output',
        line: 'Session 2 output',
        session_id: 2
      })

      await waitFor(() => {
        expect(screen.getByText('Session 1 output')).toBeInTheDocument()
      })

      // Session 2's output should not be visible while viewing session 1
      expect(screen.queryByText('Session 2 output')).not.toBeInTheDocument()
    })
  })
})
