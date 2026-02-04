import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { ResultMessage } from '../../../src/components/conversation/result-message'
import type { ResultMessage as ResultMessageType } from '../../../src/types'

describe('ResultMessage', () => {
  it('renders success state with green styling', () => {
    const message: ResultMessageType = {
      type: 'result',
      subtype: 'success'
    }

    const { container } = render(<ResultMessage message={message} />)
    expect(screen.getByText('Completed successfully')).toBeInTheDocument()
    // Check for success styling class
    const wrapper = container.firstChild as HTMLElement
    expect(wrapper.className).toContain('text-emerald')
    expect(wrapper.className).toContain('border-emerald')
  })

  it('renders error state with red styling', () => {
    const message: ResultMessageType = {
      type: 'result',
      subtype: 'error'
    }

    const { container } = render(<ResultMessage message={message} />)
    expect(screen.getByText('Failed')).toBeInTheDocument()
    // Check for error styling class
    const wrapper = container.firstChild as HTMLElement
    expect(wrapper.className).toContain('text-red')
    expect(wrapper.className).toContain('border-red')
  })

  it('displays result text when provided', () => {
    const message: ResultMessageType = {
      type: 'result',
      subtype: 'success',
      result: 'Task completed in 5 seconds'
    }

    render(<ResultMessage message={message} />)
    expect(screen.getByText('Completed successfully')).toBeInTheDocument()
    expect(screen.getByText(/Task completed in 5 seconds/)).toBeInTheDocument()
  })
})
