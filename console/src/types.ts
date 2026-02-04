// API types - validated via Rails runner

export interface Session {
  id: number
  sandbox_id: number
  session_uuid: string
  title: string | null
  display_name: string
  git_diff: string | null
  created_at: string
  updated_at: string
}

export interface ExecutionHistory {
  id: number
  exit_code: number | null
  logs: string[]
}

export interface SessionWithHistory extends Session {
  history: ExecutionHistory[]
}

export interface Config {
  sandboxId: string
  wsUrl: string
  token: string
  apiUrl: string
}

export interface OutputLine {
  id: string
  text: string
  timestamp: number
}

// Claude streaming JSON types

export interface UserMessage {
  type: 'user'
  text: string
}

export interface SystemMessage {
  type: 'system'
  subtype: 'init'
  cwd: string
  session_id?: string
}

export interface TextContent {
  type: 'text'
  text: string
}

export interface ThinkingContent {
  type: 'thinking'
  thinking: string
}

export interface ToolUseContent {
  type: 'tool_use'
  id: string
  name: string
  input: Record<string, unknown>
}

export type ContentBlock = TextContent | ThinkingContent | ToolUseContent

export interface AssistantMessage {
  type: 'assistant'
  message: {
    content: ContentBlock[]
  }
}

export interface ResultMessage {
  type: 'result'
  subtype: 'success' | 'error' | 'error_during_execution'
  result?: string
  is_error?: boolean
  errors?: string[]
}

export type ClaudeMessage = UserMessage | SystemMessage | AssistantMessage | ResultMessage

export interface ConversationEntry {
  id: string
  raw: string
  parsed: ClaudeMessage | null
  error?: string
}
