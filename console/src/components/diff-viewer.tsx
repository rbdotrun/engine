import { useState, useMemo } from 'react'
import { X, FileCode, FilePlus, FileMinus, FileEdit } from 'lucide-react'

interface DiffViewerProps {
  diff: string
  onClose: () => void
}

interface FileDiff {
  path: string
  status: 'added' | 'deleted' | 'modified'
  content: string
  additions: number
  deletions: number
}

export function DiffViewer({ diff, onClose }: DiffViewerProps) {
  const files = useMemo(() => parseDiff(diff), [diff])
  const [selectedFile, setSelectedFile] = useState<string | null>(files[0]?.path ?? null)

  const currentFile = files.find(f => f.path === selectedFile)

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70">
      <div className="relative w-[95%] max-w-6xl h-[85vh] bg-neutral-900 border border-neutral-700 rounded-lg shadow-2xl flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-neutral-700">
          <div className="flex items-center gap-3">
            <span className="text-sm font-medium text-neutral-200">Changes</span>
            <span className="text-xs text-neutral-500">
              {files.length} file{files.length !== 1 ? 's' : ''} changed
            </span>
          </div>
          <button
            onClick={onClose}
            className="p-1 text-neutral-400 hover:text-white transition-colors rounded hover:bg-neutral-800"
          >
            <X size={18} />
          </button>
        </div>

        {/* Content */}
        <div className="flex-1 flex overflow-hidden">
          {/* File list sidebar */}
          <div className="w-64 border-r border-neutral-700 overflow-y-auto flex-shrink-0">
            {files.map(file => (
              <button
                key={file.path}
                onClick={() => setSelectedFile(file.path)}
                className={`w-full flex items-center gap-2 px-3 py-2 text-left text-xs transition-colors ${
                  selectedFile === file.path
                    ? 'bg-neutral-800 text-white'
                    : 'text-neutral-400 hover:bg-neutral-800/50 hover:text-neutral-200'
                }`}
              >
                <FileIcon status={file.status} />
                <span className="flex-1 truncate font-mono">{file.path}</span>
                <span className="flex gap-1 text-[10px]">
                  {file.additions > 0 && (
                    <span className="text-emerald-400">+{file.additions}</span>
                  )}
                  {file.deletions > 0 && (
                    <span className="text-red-400">-{file.deletions}</span>
                  )}
                </span>
              </button>
            ))}
          </div>

          {/* Diff content */}
          <div className="flex-1 overflow-auto p-4 font-mono text-xs leading-relaxed">
              {currentFile ? (
                currentFile.content.split('\n').map((line, i) => (
                  <div key={i} className={getLineClass(line)}>
                    {line || ' '}
                  </div>
                ))
              ) : (
                <div className="text-neutral-500 text-center py-8">
                Select a file to view changes
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

function FileIcon({ status }: { status: FileDiff['status'] }) {
  switch (status) {
    case 'added':
      return <FilePlus size={14} className="text-emerald-400 flex-shrink-0" />
    case 'deleted':
      return <FileMinus size={14} className="text-red-400 flex-shrink-0" />
    default:
      return <FileEdit size={14} className="text-amber-400 flex-shrink-0" />
  }
}

function parseDiff(diff: string): FileDiff[] {
  const files: FileDiff[] = []
  const fileDiffs = diff.split(/^diff --git /m).filter(Boolean)

  for (const fileDiff of fileDiffs) {
    const lines = fileDiff.split('\n')
    const headerLine = lines[0] || ''

    // Extract file path from "a/path b/path"
    const pathMatch = headerLine.match(/a\/(.+?) b\//)
    const path = pathMatch?.[1] || headerLine.split(' ')[0]?.replace('a/', '') || 'unknown'

    // Determine status
    let status: FileDiff['status'] = 'modified'
    if (fileDiff.includes('new file mode')) {
      status = 'added'
    } else if (fileDiff.includes('deleted file mode')) {
      status = 'deleted'
    }

    // Count additions/deletions
    let additions = 0
    let deletions = 0
    for (const line of lines) {
      if (line.startsWith('+') && !line.startsWith('+++')) additions++
      if (line.startsWith('-') && !line.startsWith('---')) deletions++
    }

    // Keep content without the "diff --git" prefix (we'll show it cleaner)
    const content = lines.slice(1).join('\n').trim()

    files.push({ path, status, content, additions, deletions })
  }

  return files
}

function getLineClass(line: string): string {
  const base = 'px-2 whitespace-pre'
  if (line.startsWith('+++') || line.startsWith('---')) {
    return `${base} text-neutral-500`
  }
  if (line.startsWith('@@')) {
    return `${base} text-blue-400 bg-blue-500/10`
  }
  if (line.startsWith('+')) {
    return `${base} text-emerald-400 bg-emerald-500/10`
  }
  if (line.startsWith('-')) {
    return `${base} text-red-400 bg-red-500/10`
  }
  if (line.startsWith('index ') || line.startsWith('new file') || line.startsWith('deleted file')) {
    return `${base} text-neutral-600`
  }
  return `${base} text-neutral-300`
}
