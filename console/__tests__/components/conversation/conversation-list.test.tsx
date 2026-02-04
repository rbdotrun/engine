import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { ConversationList } from '../../../src/components/conversation/conversation-list'
import { ConversationItem } from '../../../src/components/conversation/conversation-item'
import type { ConversationEntry } from '../../../src/types'

// Mock data validated via Rails runner
const userMessageLog = '{"type":"user","text":"Hello Claude!"}'
const systemInitLog = '{"type":"system","subtype":"init","cwd":"/home/user"}'
const assistantTextLog = '{"type":"assistant","message":{"content":[{"type":"text","text":"Hello world!"}]}}'
const resultSuccessLog = '{"type":"result","subtype":"success"}'
const malformedLog = 'not valid json'

describe('ConversationList', () => {
  it('renders empty state when logs array is empty', () => {
    render(<ConversationList logs={[]} />)
    expect(screen.getByText('No messages yet')).toBeInTheDocument()
  })

  it('parses valid JSON lines into conversation entries', () => {
    render(<ConversationList logs={[systemInitLog]} />)
    expect(screen.getByText(/Session initialized/)).toBeInTheDocument()
    expect(screen.getByText('/home/user')).toBeInTheDocument()
  })

  it('handles malformed JSON gracefully with error display', () => {
    render(<ConversationList logs={[malformedLog]} />)
    expect(screen.getByText('Invalid JSON')).toBeInTheDocument()
    expect(screen.getByText(malformedLog)).toBeInTheDocument()
  })

  it('renders multiple entries in order', () => {
    render(
      <ConversationList
        logs={[systemInitLog, assistantTextLog, resultSuccessLog]}
      />
    )

    expect(screen.getByText(/Session initialized/)).toBeInTheDocument()
    expect(screen.getByText('Hello world!')).toBeInTheDocument()
    expect(screen.getByText('Completed successfully')).toBeInTheDocument()
  })
})

describe('ConversationItem', () => {
  it('renders UserMessage for type user', () => {
    const entry: ConversationEntry = {
      id: 'test-0',
      raw: userMessageLog,
      parsed: { type: 'user', text: 'Hello Claude!' }
    }

    render(<ConversationItem entry={entry} />)
    expect(screen.getByText('Hello Claude!')).toBeInTheDocument()
  })

  it('renders SystemMessage for type system', () => {
    const entry: ConversationEntry = {
      id: 'test-1',
      raw: systemInitLog,
      parsed: { type: 'system', subtype: 'init', cwd: '/home/user' }
    }

    render(<ConversationItem entry={entry} />)
    expect(screen.getByText(/Session initialized/)).toBeInTheDocument()
    expect(screen.getByText('/home/user')).toBeInTheDocument()
  })

  it('renders AssistantMessage for type assistant', () => {
    const entry: ConversationEntry = {
      id: 'test-2',
      raw: assistantTextLog,
      parsed: {
        type: 'assistant',
        message: {
          content: [{ type: 'text', text: 'Hello from Claude!' }]
        }
      }
    }

    render(<ConversationItem entry={entry} />)
    expect(screen.getByText('Hello from Claude!')).toBeInTheDocument()
  })

  it('renders ResultMessage for type result', () => {
    const entry: ConversationEntry = {
      id: 'test-3',
      raw: resultSuccessLog,
      parsed: { type: 'result', subtype: 'success' }
    }

    render(<ConversationItem entry={entry} />)
    expect(screen.getByText('Completed successfully')).toBeInTheDocument()
  })

  it('renders error state for unparseable entry', () => {
    const entry: ConversationEntry = {
      id: 'test-4',
      raw: 'invalid json',
      parsed: null,
      error: 'Invalid JSON'
    }

    render(<ConversationItem entry={entry} />)
    expect(screen.getByText('Invalid JSON')).toBeInTheDocument()
    expect(screen.getByText('invalid json')).toBeInTheDocument()
  })
})
