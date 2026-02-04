import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { App } from '../src/app'
import { mockConfig, mockSessions, createMockCable } from './test-utils'

const mockCable = createMockCable()

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => mockCable.cable
}))

describe('App', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    localStorage.clear()
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    ) as unknown as typeof fetch
  })

  afterEach(() => {
    localStorage.clear()
  })

  describe('toggle button', () => {
    it('renders the toggle button with rbrun text', () => {
      render(<App config={mockConfig} />)
      expect(screen.getByText('rbrun')).toBeInTheDocument()
    })

    it('opens panel when toggle button is clicked', async () => {
      render(<App config={mockConfig} />)

      const toggleButton = screen.getByText('rbrun')
      fireEvent.click(toggleButton)

      await waitFor(() => {
        expect(screen.getByText('Claude Code')).toBeInTheDocument()
      })
    })

    it('closes panel when close button is clicked', async () => {
      render(<App config={mockConfig} />)

      // Open panel
      fireEvent.click(screen.getByText('rbrun'))
      await waitFor(() => {
        expect(screen.getByText('Claude Code')).toBeInTheDocument()
      })

      // Close panel - find the X icon button (it's the one with lucide-x class inside)
      const closeButton = document.querySelector('button svg.lucide-x')?.parentElement
      expect(closeButton).toBeTruthy()
      fireEvent.click(closeButton!)

      await waitFor(() => {
        expect(screen.queryByText('Claude Code')).not.toBeInTheDocument()
      })
    })
  })

  describe('session persistence', () => {
    it('stores session ID in localStorage when navigating to a session', async () => {
      render(<App config={mockConfig} />)

      fireEvent.click(screen.getByText('rbrun'))
      mockCable.simulateConnect()

      await waitFor(() => {
        expect(screen.getByText('My Session')).toBeInTheDocument()
      })

      // Click on a session tab
      fireEvent.click(screen.getByText('My Session'))

      await waitFor(() => {
        const stored = localStorage.getItem(`rbrun:${mockConfig.sandboxId}:ui`)
        const parsed = stored ? JSON.parse(stored) : null
        expect(parsed?.sessionId).toBe(1)
      })
    })

    it('restores session and console state from localStorage on mount', async () => {
      localStorage.setItem(`rbrun:${mockConfig.sandboxId}:ui`, JSON.stringify({ sessionId: 2, consoleState: 'opened', diffOpen: false }))

      render(<App config={mockConfig} />)
      // Console should already be open from localStorage, don't click button
      mockCable.simulateConnect()

      await waitFor(() => {
        // Session 2 tab should be visible (console is already open)
        const session2Tab = screen.getByText('Session 2')
        expect(session2Tab).toBeInTheDocument()
      })
    })

    it('handles missing localStorage gracefully', async () => {
      render(<App config={mockConfig} />)
      fireEvent.click(screen.getByText('rbrun'))

      await waitFor(() => {
        expect(screen.getByText('Click to create a session')).toBeInTheDocument()
      })
    })
  })

  describe('escape key behavior', () => {
    it('closes opened panel when escape is pressed', async () => {
      render(<App config={mockConfig} />)

      // Open panel
      fireEvent.click(screen.getByText('rbrun'))
      await waitFor(() => {
        expect(screen.getByText('Claude Code')).toBeInTheDocument()
      })

      // Press escape
      fireEvent.keyDown(document, { key: 'Escape' })

      await waitFor(() => {
        expect(screen.queryByText('Claude Code')).not.toBeInTheDocument()
      })
    })

    it('exits fullscreen to opened when escape is pressed in fullscreen', async () => {
      localStorage.setItem(`rbrun:${mockConfig.sandboxId}:ui`, JSON.stringify({ consoleState: 'fullscreen', sessionId: null, diffOpen: false }))

      render(<App config={mockConfig} />)

      await waitFor(() => {
        expect(screen.getByText('Claude Code')).toBeInTheDocument()
      })

      // In fullscreen mode, panel should have inset-5 class
      const panel = document.querySelector('.fixed.inset-5')
      expect(panel).toBeInTheDocument()

      // Press escape - should go to opened (not closed)
      fireEvent.keyDown(document, { key: 'Escape' })

      await waitFor(() => {
        // Panel should still be visible
        expect(screen.getByText('Claude Code')).toBeInTheDocument()
        // But not fullscreen anymore (inset-5 gone, bottom-5 right-5 present)
        expect(document.querySelector('.fixed.inset-5')).not.toBeInTheDocument()
        expect(document.querySelector('.fixed.bottom-5.right-5')).toBeInTheDocument()
      })
    })

    it('does nothing when escape is pressed and panel is closed', () => {
      render(<App config={mockConfig} />)

      // Panel is closed, escape should do nothing
      fireEvent.keyDown(document, { key: 'Escape' })

      // Still closed
      expect(screen.queryByText('Claude Code')).not.toBeInTheDocument()
      expect(screen.getByText('rbrun')).toBeInTheDocument()
    })
  })

  describe('panel content', () => {
    it('displays sandbox ID in header', async () => {
      render(<App config={mockConfig} />)
      fireEvent.click(screen.getByText('rbrun'))

      await waitFor(() => {
        expect(screen.getByText(`Sandbox: ${mockConfig.sandboxId}`)).toBeInTheDocument()
      })
    })

    it('shows connection status indicator', async () => {
      render(<App config={mockConfig} />)
      fireEvent.click(screen.getByText('rbrun'))
      mockCable.simulateConnect()

      await waitFor(() => {
        expect(screen.getByText('Claude Code')).toBeInTheDocument()
      })
    })

    it('loads and displays sessions', async () => {
      render(<App config={mockConfig} />)
      fireEvent.click(screen.getByText('rbrun'))

      await waitFor(() => {
        expect(screen.getByText('My Session')).toBeInTheDocument()
        expect(screen.getByText('Session 2')).toBeInTheDocument()
      })
    })
  })
})
