import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, act } from '@testing-library/react'
import { useConsole, ConsoleProvider } from '../../src/context/console-context'
import { mockConfig, createMockCable } from '../test-utils'

const mockCable = createMockCable()

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => mockCable.cable
}))

function TestConsumer() {
  const { config, connected, activeSessionId, outputBySession, setActiveSessionId, runClaude, appendOutput } = useConsole()

  return (
    <div>
      <div data-testid="config">{JSON.stringify(config)}</div>
      <div data-testid="connected">{connected.toString()}</div>
      <div data-testid="activeSessionId">{activeSessionId ?? 'null'}</div>
      <div data-testid="output">{JSON.stringify(outputBySession)}</div>
      <button onClick={() => setActiveSessionId(1)}>Set Session 1</button>
      <button onClick={() => setActiveSessionId(null)}>Clear Session</button>
      <button onClick={() => runClaude('test prompt', 1)}>Run Claude</button>
      <button onClick={() => appendOutput(1, 'test output')}>Append Output</button>
    </div>
  )
}

describe('ConsoleContext', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  describe('ConsoleProvider', () => {
    it('provides config to consumers', () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      const configEl = screen.getByTestId('config')
      expect(JSON.parse(configEl.textContent!)).toEqual(mockConfig)
    })

    it('starts disconnected', () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      expect(screen.getByTestId('connected').textContent).toBe('false')
    })

    it('updates connected state when ActionCable connects', async () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      act(() => {
        mockCable.simulateConnect()
      })

      await waitFor(() => {
        expect(screen.getByTestId('connected').textContent).toBe('true')
      })
    })

    it('updates connected state when ActionCable disconnects', async () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      act(() => {
        mockCable.simulateConnect()
      })

      await waitFor(() => {
        expect(screen.getByTestId('connected').textContent).toBe('true')
      })

      act(() => {
        mockCable.simulateDisconnect()
      })

      await waitFor(() => {
        expect(screen.getByTestId('connected').textContent).toBe('false')
      })
    })
  })

  describe('useConsole hook', () => {
    it('throws error when used outside provider', () => {
      const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})

      expect(() => render(<TestConsumer />)).toThrow('useConsole must be used within ConsoleProvider')

      consoleError.mockRestore()
    })
  })

  describe('activeSessionId', () => {
    it('starts with null active session', () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      expect(screen.getByTestId('activeSessionId').textContent).toBe('null')
    })

    it('updates active session via setActiveSessionId', async () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      screen.getByText('Set Session 1').click()

      await waitFor(() => {
        expect(screen.getByTestId('activeSessionId').textContent).toBe('1')
      })
    })

    it('clears active session', async () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      screen.getByText('Set Session 1').click()
      await waitFor(() => {
        expect(screen.getByTestId('activeSessionId').textContent).toBe('1')
      })

      screen.getByText('Clear Session').click()
      await waitFor(() => {
        expect(screen.getByTestId('activeSessionId').textContent).toBe('null')
      })
    })
  })

  describe('output management', () => {
    it('starts with empty output', () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      expect(JSON.parse(screen.getByTestId('output').textContent!)).toEqual({})
    })

    it('appends output to correct session', async () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      screen.getByText('Append Output').click()

      await waitFor(() => {
        const output = JSON.parse(screen.getByTestId('output').textContent!)
        expect(output[1]).toHaveLength(1)
        expect(output[1][0].text).toBe('test output')
      })
    })

    it('maintains separate output per session', async () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      // Append to session 1
      screen.getByText('Append Output').click()

      await waitFor(() => {
        const output = JSON.parse(screen.getByTestId('output').textContent!)
        expect(output[1]).toHaveLength(1)
        expect(output[2]).toBeUndefined()
      })
    })
  })

  describe('ActionCable message handling', () => {
    it('handles output messages', async () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      act(() => {
        mockCable.simulateConnect()
        mockCable.simulateMessage({
          type: 'output',
          line: 'test line',
          session_id: 1
        })
      })

      await waitFor(() => {
        const output = JSON.parse(screen.getByTestId('output').textContent!)
        expect(output[1]?.[0]?.text).toBe('test line')
      })
    })

    it('ignores complete messages (status signal only)', async () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      act(() => {
        mockCable.simulateConnect()
        mockCable.simulateMessage({
          type: 'complete',
          success: true,
          session_id: 1
        })
      })

      // Complete is a status signal, not added to output
      await waitFor(() => {
        const output = JSON.parse(screen.getByTestId('output').textContent!)
        expect(output[1]).toBeUndefined()
      })
    })

    it('handles error messages as JSON result', async () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      act(() => {
        mockCable.simulateConnect()
        mockCable.simulateMessage({
          type: 'error',
          message: 'Something went wrong',
          session_id: 1
        })
      })

      await waitFor(() => {
        const output = JSON.parse(screen.getByTestId('output').textContent!)
        const parsed = JSON.parse(output[1]?.[0]?.text)
        expect(parsed.type).toBe('result')
        expect(parsed.subtype).toBe('error')
        expect(parsed.errors).toContain('Something went wrong')
      })
    })

    it('handles session_created messages', async () => {
      const onSessionCreated = vi.fn()

      render(
        <ConsoleProvider config={mockConfig} onSessionCreated={onSessionCreated}>
          <TestConsumer />
        </ConsoleProvider>
      )

      act(() => {
        mockCable.simulateConnect()
        mockCable.simulateMessage({
          type: 'session_created',
          session: { id: 5, display_name: 'New Session' }
        })
      })

      await waitFor(() => {
        expect(onSessionCreated).toHaveBeenCalledWith({ id: 5, display_name: 'New Session' })
      })
    })
  })

  describe('runClaude', () => {
    it('calls ActionCable perform with prompt and session_id', async () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      act(() => {
        mockCable.simulateConnect()
      })

      screen.getByText('Run Claude').click()

      await waitFor(() => {
        expect(mockCable.subscription.perform).toHaveBeenCalledWith('run_claude', {
          prompt: 'test prompt',
          session_id: 1
        })
      })
    })

    it('does not add prompt locally (waits for backend broadcast)', async () => {
      render(
        <ConsoleProvider config={mockConfig}>
          <TestConsumer />
        </ConsoleProvider>
      )

      act(() => {
        mockCable.simulateConnect()
      })

      screen.getByText('Run Claude').click()

      // Prompt is NOT added locally - backend saves and broadcasts it
      await waitFor(() => {
        const output = JSON.parse(screen.getByTestId('output').textContent!)
        expect(output[1]).toBeUndefined()
      })
    })
  })
})
