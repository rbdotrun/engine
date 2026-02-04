// Centralized UI state persistence
// All display-related state that should survive page reloads

export type ConsoleState = 'closed' | 'opened' | 'fullscreen'

export interface UIState {
  consoleState: ConsoleState
  sessionId: number | null
  diffOpen: boolean
}

const DEFAULT_STATE: UIState = {
  consoleState: 'closed',
  sessionId: null,
  diffOpen: false
}

function getStorageKey(sandboxId: string): string {
  return `rbrun:${sandboxId}:ui`
}

export function loadUIState(sandboxId: string): UIState {
  try {
    const raw = localStorage.getItem(getStorageKey(sandboxId))
    if (raw) {
      const parsed = JSON.parse(raw)
      return {
        consoleState: parsed.consoleState ?? DEFAULT_STATE.consoleState,
        sessionId: parsed.sessionId ?? DEFAULT_STATE.sessionId,
        diffOpen: parsed.diffOpen ?? DEFAULT_STATE.diffOpen
      }
    }
  } catch {}
  return DEFAULT_STATE
}

export function saveUIState(sandboxId: string, state: UIState): void {
  try {
    localStorage.setItem(getStorageKey(sandboxId), JSON.stringify(state))
  } catch {}
}
