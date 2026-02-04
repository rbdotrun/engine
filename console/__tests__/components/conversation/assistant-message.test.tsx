import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { AssistantMessage } from '../../../src/components/conversation/assistant-message'
import { TextContent } from '../../../src/components/conversation/text-content'
import { ThinkingContent } from '../../../src/components/conversation/thinking-content'
import { ToolUseContent } from '../../../src/components/conversation/tool-use-content'
import type { AssistantMessage as AssistantMessageType, TextContent as TextContentType, ThinkingContent as ThinkingContentType, ToolUseContent as ToolUseContentType } from '../../../src/types'

describe('AssistantMessage', () => {
  it('renders text content blocks', () => {
    const message: AssistantMessageType = {
      type: 'assistant',
      message: {
        content: [{ type: 'text', text: 'Hello, I can help you!' }]
      }
    }

    render(<AssistantMessage message={message} />)
    expect(screen.getByText('Hello, I can help you!')).toBeInTheDocument()
  })

  it('renders thinking content blocks', () => {
    const message: AssistantMessageType = {
      type: 'assistant',
      message: {
        content: [{ type: 'thinking', thinking: 'Let me consider this...' }]
      }
    }

    render(<AssistantMessage message={message} />)
    expect(screen.getByText('Thinking')).toBeInTheDocument()
    expect(screen.getByText('Let me consider this...')).toBeInTheDocument()
  })

  it('renders tool_use content blocks', () => {
    const message: AssistantMessageType = {
      type: 'assistant',
      message: {
        content: [
          {
            type: 'tool_use',
            id: 'tool-123',
            name: 'Read',
            input: { file_path: '/path/to/file.txt' }
          }
        ]
      }
    }

    render(<AssistantMessage message={message} />)
    expect(screen.getByText('Read')).toBeInTheDocument()
    expect(screen.getByText(/file_path/)).toBeInTheDocument()
    expect(screen.getByText(/\/path\/to\/file\.txt/)).toBeInTheDocument()
  })

  it('renders multiple content blocks in order', () => {
    const message: AssistantMessageType = {
      type: 'assistant',
      message: {
        content: [
          { type: 'thinking', thinking: 'Thinking first...' },
          { type: 'text', text: 'Then responding.' },
          {
            type: 'tool_use',
            id: 'tool-1',
            name: 'Bash',
            input: { command: 'ls -la' }
          }
        ]
      }
    }

    render(<AssistantMessage message={message} />)
    expect(screen.getByText('Thinking')).toBeInTheDocument()
    expect(screen.getByText('Thinking first...')).toBeInTheDocument()
    expect(screen.getByText('Then responding.')).toBeInTheDocument()
    expect(screen.getByText('Bash')).toBeInTheDocument()
    expect(screen.getByText(/ls -la/)).toBeInTheDocument()
  })
})

describe('TextContent', () => {
  it('renders markdown text with Streamdown', () => {
    const content: TextContentType = { type: 'text', text: 'Hello **bold** text' }
    render(<TextContent content={content} />)
    expect(screen.getByText(/Hello/)).toBeInTheDocument()
    expect(screen.getByText('bold')).toBeInTheDocument()
  })

  it('renders code blocks container', () => {
    const content: TextContentType = {
      type: 'text',
      text: '```javascript\nconst x = 1;\n```'
    }
    const { container } = render(<TextContent content={content} />)
    // Streamdown renders code blocks with async highlighting
    // Just verify the component renders without error
    expect(container.querySelector('.prose')).toBeInTheDocument()
  })
})

describe('ThinkingContent', () => {
  it('renders thinking text with lightbulb icon', () => {
    const content: ThinkingContentType = {
      type: 'thinking',
      thinking: 'Considering the options...'
    }

    render(<ThinkingContent content={content} />)
    expect(screen.getByText('Considering the options...')).toBeInTheDocument()
  })

  it('displays "Thinking" header', () => {
    const content: ThinkingContentType = {
      type: 'thinking',
      thinking: 'Some thought process'
    }

    render(<ThinkingContent content={content} />)
    expect(screen.getByText('Thinking')).toBeInTheDocument()
  })
})

describe('ToolUseContent', () => {
  it('renders tool name with wrench icon', () => {
    const content: ToolUseContentType = {
      type: 'tool_use',
      id: 'tool-abc',
      name: 'Write',
      input: { file_path: '/test.txt', content: 'hello' }
    }

    render(<ToolUseContent content={content} />)
    expect(screen.getByText('Write')).toBeInTheDocument()
  })

  it('displays input as formatted JSON', () => {
    const content: ToolUseContentType = {
      type: 'tool_use',
      id: 'tool-xyz',
      name: 'Edit',
      input: {
        file_path: '/src/app.ts',
        old_string: 'foo',
        new_string: 'bar'
      }
    }

    render(<ToolUseContent content={content} />)
    expect(screen.getByText('Edit')).toBeInTheDocument()
    expect(screen.getByText(/file_path/)).toBeInTheDocument()
    expect(screen.getByText(/old_string/)).toBeInTheDocument()
    expect(screen.getByText(/new_string/)).toBeInTheDocument()
  })
})
