import { Streamdown } from 'streamdown'
import { code } from '@streamdown/code'

interface MarkdownProps {
  children: string
  isStreaming?: boolean
}

export function Markdown({ children, isStreaming = false }: MarkdownProps) {
  return (
    <Streamdown
      plugins={[code]}
      isAnimating={isStreaming}
    >
      {children}
    </Streamdown>
  )
}
