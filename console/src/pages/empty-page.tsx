import { Plus } from 'lucide-react'
import { useNavigate } from 'react-router'
import { useCreateSession } from '../hooks/use-sessions'

export function EmptyPage() {
  const navigate = useNavigate()
  const createSession = useCreateSession()

  const handleClick = async () => {
    try {
      const session = await createSession.mutateAsync()
      navigate(`/sessions/${session.id}`)
    } catch (error) {
      console.error('Failed to create session:', error)
    }
  }

  return (
    <button
      onClick={handleClick}
      disabled={createSession.isPending}
      className="flex-1 flex flex-col items-center justify-center text-neutral-500 gap-2 w-full bg-transparent border-none cursor-pointer hover:text-neutral-400 transition-colors disabled:cursor-wait"
    >
      <Plus size={24} className="text-neutral-600" />
      <p>Click to create a session</p>
    </button>
  )
}
