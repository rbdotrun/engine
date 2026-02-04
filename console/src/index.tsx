import { createRoot } from 'react-dom/client'
import './index.css'
import { App } from './app'

declare global {
  interface Window {
    RBRUN_CONFIG?: {
      sandboxId: string
      wsUrl: string
      apiUrl: string
      token: string
    }
  }
}

if (window.RBRUN_CONFIG) {
  let container = document.getElementById('rbrun-console-root')
  if (!container) {
    container = document.createElement('div')
    container.id = 'rbrun-console-root'
    document.body.appendChild(container)
  }
  createRoot(container).render(<App config={window.RBRUN_CONFIG} />)
}
