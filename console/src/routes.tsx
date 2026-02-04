import { Routes, Route } from 'react-router'
import { ConsoleLayout } from './layouts/console-layout'
import { SessionPage } from './pages/session-page'
import { EmptyPage } from './pages/empty-page'

export function AppRoutes() {
  return (
    <Routes>
      <Route element={<ConsoleLayout />}>
        <Route index element={<EmptyPage />} />
        <Route path="sessions/:sessionId" element={<SessionPage />} />
      </Route>
    </Routes>
  )
}
