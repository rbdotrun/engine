import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { SessionTabs } from '../../src/components/session-tabs'
import { mockSessions } from '../test-utils'

describe('SessionTabs', () => {
  const defaultProps = {
    sessions: mockSessions,
    activeSessionId: null as number | null,
    onSelect: vi.fn(),
    onCreate: vi.fn(),
    loading: false
  }

  beforeEach(() => {
    vi.clearAllMocks()
  })

  describe('rendering', () => {
    it('renders all session tabs', () => {
      render(<SessionTabs {...defaultProps} />)

      expect(screen.getByText('My Session')).toBeInTheDocument()
      expect(screen.getByText('Session 2')).toBeInTheDocument()
    })

    it('renders add button', () => {
      render(<SessionTabs {...defaultProps} />)

      const addButton = screen.getByTitle('New session')
      expect(addButton).toBeInTheDocument()
    })

    it('renders empty state when no sessions', () => {
      render(<SessionTabs {...defaultProps} sessions={[]} />)

      // Should only have the add button
      const buttons = screen.getAllByRole('button')
      expect(buttons).toHaveLength(1)
      expect(buttons[0]).toHaveAttribute('title', 'New session')
    })
  })

  describe('active state', () => {
    it('highlights active session tab', () => {
      render(<SessionTabs {...defaultProps} activeSessionId={1} />)

      const activeTab = screen.getByText('My Session')
      expect(activeTab.className).toContain('bg-emerald-500')
    })

    it('does not highlight inactive session tabs', () => {
      render(<SessionTabs {...defaultProps} activeSessionId={1} />)

      const inactiveTab = screen.getByText('Session 2')
      expect(inactiveTab.className).not.toContain('bg-emerald-500')
    })
  })

  describe('interactions', () => {
    it('calls onSelect when clicking a session tab', () => {
      const onSelect = vi.fn()
      render(<SessionTabs {...defaultProps} onSelect={onSelect} />)

      fireEvent.click(screen.getByText('My Session'))

      expect(onSelect).toHaveBeenCalledWith(1)
    })

    it('calls onSelect with correct session id', () => {
      const onSelect = vi.fn()
      render(<SessionTabs {...defaultProps} onSelect={onSelect} />)

      fireEvent.click(screen.getByText('Session 2'))

      expect(onSelect).toHaveBeenCalledWith(2)
    })

    it('calls onCreate when clicking add button', () => {
      const onCreate = vi.fn()
      render(<SessionTabs {...defaultProps} onCreate={onCreate} />)

      fireEvent.click(screen.getByTitle('New session'))

      expect(onCreate).toHaveBeenCalledTimes(1)
    })
  })

  describe('loading state', () => {
    it('disables add button when loading', () => {
      render(<SessionTabs {...defaultProps} loading={true} />)

      const addButton = screen.getByTitle('New session')
      expect(addButton).toBeDisabled()
    })

    it('enables add button when not loading', () => {
      render(<SessionTabs {...defaultProps} loading={false} />)

      const addButton = screen.getByTitle('New session')
      expect(addButton).not.toBeDisabled()
    })

    it('does not call onCreate when clicking disabled add button', () => {
      const onCreate = vi.fn()
      render(<SessionTabs {...defaultProps} onCreate={onCreate} loading={true} />)

      fireEvent.click(screen.getByTitle('New session'))

      expect(onCreate).not.toHaveBeenCalled()
    })
  })

  describe('display_name', () => {
    it('uses title when available', () => {
      render(<SessionTabs {...defaultProps} />)

      expect(screen.getByText('My Session')).toBeInTheDocument()
    })

    it('uses fallback display_name when title is null', () => {
      render(<SessionTabs {...defaultProps} />)

      // Session 2 has null title, display_name is "Session 2"
      expect(screen.getByText('Session 2')).toBeInTheDocument()
    })
  })
})
