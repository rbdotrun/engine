import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent, waitFor } from '@testing-library/react'
import { EmptyPage } from '../../src/pages/empty-page'
import { renderWithProviders, mockSessions, createMockCable } from '../test-utils'

const mockCable = createMockCable()

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => mockCable.cable
}))

describe('EmptyPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockSessions)
      })
    ) as unknown as typeof fetch
  })

  it('renders placeholder text', () => {
    renderWithProviders(<EmptyPage />)
    expect(screen.getByText('Click to create a session')).toBeInTheDocument()
  })

  it('renders plus icon', () => {
    renderWithProviders(<EmptyPage />)
    const svg = document.querySelector('svg')
    expect(svg).toBeInTheDocument()
  })

  it('renders as a clickable button', () => {
    renderWithProviders(<EmptyPage />)
    const button = screen.getByRole('button')
    expect(button).toBeInTheDocument()
  })

  it('creates session when clicked', async () => {
    const newSession = {
      id: 3,
      sandbox_id: 1,
      session_uuid: 'uuid-3',
      title: null,
      display_name: 'Session 3',
      created_at: '2024-01-03T00:00:00Z',
      updated_at: '2024-01-03T00:00:00Z'
    }

    global.fetch = vi.fn((url: string, options?: RequestInit) => {
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

    renderWithProviders(<EmptyPage />)

    const button = screen.getByRole('button')
    fireEvent.click(button)

    await waitFor(() => {
      const postCalls = (global.fetch as any).mock.calls.filter(
        ([, opts]: [string, RequestInit?]) => opts?.method === 'POST'
      )
      expect(postCalls.length).toBeGreaterThan(0)
    })
  })
})
