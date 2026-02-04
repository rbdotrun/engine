import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { fetchSessionHistory } from './use-sessions'

describe('fetchSessionHistory', () => {
  const mockFetch = vi.fn()

  beforeEach(() => {
    vi.stubGlobal('fetch', mockFetch)
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    mockFetch.mockReset()
  })

  it('fetches session with history from correct URL', async () => {
    const mockSession = {
      id: 1,
      sandbox_id: 42,
      session_uuid: 'abc-123',
      title: 'Test Session',
      display_name: 'Test Session',
      created_at: '2024-01-01T00:00:00Z',
      updated_at: '2024-01-01T00:00:00Z',
      history: [
        { id: 100, exit_code: 0, logs: ['line 1', 'line 2'] },
        { id: 101, exit_code: 1, logs: ['error'] }
      ]
    }

    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockSession)
    })

    const result = await fetchSessionHistory('http://api.test', '42', 1)

    expect(mockFetch).toHaveBeenCalledWith('http://api.test/sandboxes/42/sessions/1')
    expect(result).toEqual(mockSession)
    expect(result.history).toHaveLength(2)
    expect(result.history[0].logs).toEqual(['line 1', 'line 2'])
  })

  it('throws error on failed fetch', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404
    })

    await expect(fetchSessionHistory('http://api.test', '42', 999))
      .rejects.toThrow('Failed to fetch session history')
  })

  it('returns empty history array when no executions', async () => {
    const mockSession = {
      id: 2,
      sandbox_id: 42,
      session_uuid: 'def-456',
      title: null,
      display_name: 'Session 2',
      created_at: '2024-01-01T00:00:00Z',
      updated_at: '2024-01-01T00:00:00Z',
      history: []
    }

    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockSession)
    })

    const result = await fetchSessionHistory('http://api.test', '42', 2)

    expect(result.history).toEqual([])
  })
})
