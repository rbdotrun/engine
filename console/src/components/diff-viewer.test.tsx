import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { DiffViewer } from './diff-viewer'

const MOCK_DIFF = `diff --git a/app/models/user.rb b/app/models/user.rb
index 55905bc..1b8d660 100644
--- a/app/models/user.rb
+++ b/app/models/user.rb
@@ -1,5 +1,8 @@
 class User < ApplicationRecord
-  validates :name, presence: true
+  validates :name, presence: true, length: { minimum: 2 }
+  validates :email, presence: true
+
+  has_many :posts
 end
diff --git a/app/models/post.rb b/app/models/post.rb
new file mode 100644
index 0000000..abc1234
--- /dev/null
+++ b/app/models/post.rb
@@ -0,0 +1,5 @@
+class Post < ApplicationRecord
+  belongs_to :user
+
+  validates :title, presence: true
+end
diff --git a/app/models/comment.rb b/app/models/comment.rb
deleted file mode 100644
index def5678..0000000
--- a/app/models/comment.rb
+++ /dev/null
@@ -1,3 +0,0 @@
-class Comment < ApplicationRecord
-  belongs_to :post
-end`

describe('DiffViewer', () => {
  it('renders file list with correct count', () => {
    const onClose = vi.fn()
    render(<DiffViewer diff={MOCK_DIFF} onClose={onClose} />)

    expect(screen.getByText('3 files changed')).toBeInTheDocument()
  })

  it('displays all files in sidebar', () => {
    const onClose = vi.fn()
    render(<DiffViewer diff={MOCK_DIFF} onClose={onClose} />)

    expect(screen.getByText('app/models/user.rb')).toBeInTheDocument()
    expect(screen.getByText('app/models/post.rb')).toBeInTheDocument()
    expect(screen.getByText('app/models/comment.rb')).toBeInTheDocument()
  })

  it('shows first file selected by default', () => {
    const onClose = vi.fn()
    render(<DiffViewer diff={MOCK_DIFF} onClose={onClose} />)

    // First file's diff content should be visible
    expect(screen.getByText(/validates :name, presence: true, length/)).toBeInTheDocument()
  })

  it('switches file when clicking different file', () => {
    const onClose = vi.fn()
    render(<DiffViewer diff={MOCK_DIFF} onClose={onClose} />)

    // Click on post.rb
    fireEvent.click(screen.getByText('app/models/post.rb'))

    // Should show post.rb content
    expect(screen.getByText(/class Post < ApplicationRecord/)).toBeInTheDocument()
  })

  it('calls onClose when X button clicked', () => {
    const onClose = vi.fn()
    render(<DiffViewer diff={MOCK_DIFF} onClose={onClose} />)

    const closeButton = screen.getByRole('button', { name: '' }) // X button has no text
    fireEvent.click(closeButton)

    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('shows addition/deletion counts per file', () => {
    const onClose = vi.fn()
    const { container } = render(<DiffViewer diff={MOCK_DIFF} onClose={onClose} />)

    // The sidebar shows +/- counts in text-[10px] spans
    const countSpans = container.querySelectorAll('.text-\\[10px\\] span')
    const countTexts = Array.from(countSpans).map(el => el.textContent)

    // user.rb has +4 -1, post.rb has +5, comment.rb has -3
    expect(countTexts).toContain('+4')
    expect(countTexts).toContain('-1')
    expect(countTexts).toContain('+5')
    expect(countTexts).toContain('-3')
  })

  it('handles empty diff gracefully', () => {
    const onClose = vi.fn()
    render(<DiffViewer diff="" onClose={onClose} />)

    expect(screen.getByText('0 files changed')).toBeInTheDocument()
    expect(screen.getByText('Select a file to view changes')).toBeInTheDocument()
  })

  it('renders diff lines with correct styling classes', () => {
    const onClose = vi.fn()
    const { container } = render(<DiffViewer diff={MOCK_DIFF} onClose={onClose} />)

    // Check that addition lines have emerald color class
    const additionLines = container.querySelectorAll('.text-emerald-400')
    expect(additionLines.length).toBeGreaterThan(0)

    // Check that deletion lines have red color class
    const deletionLines = container.querySelectorAll('.text-red-400')
    expect(deletionLines.length).toBeGreaterThan(0)

    // Check that hunk headers have blue color class
    const hunkHeaders = container.querySelectorAll('.text-blue-400')
    expect(hunkHeaders.length).toBeGreaterThan(0)
  })
})

describe('parseDiff edge cases', () => {
  it('handles renamed files', () => {
    const renameDiff = `diff --git a/old_name.rb b/new_name.rb
similarity index 95%
rename from old_name.rb
rename to new_name.rb
index abc123..def456 100644
--- a/old_name.rb
+++ b/new_name.rb
@@ -1,3 +1,3 @@
 class Foo
-  # old
+  # new
 end`

    const onClose = vi.fn()
    render(<DiffViewer diff={renameDiff} onClose={onClose} />)

    expect(screen.getByText('1 file changed')).toBeInTheDocument()
  })

  it('handles binary files', () => {
    const binaryDiff = `diff --git a/image.png b/image.png
new file mode 100644
index 0000000..abc1234
Binary files /dev/null and b/image.png differ`

    const onClose = vi.fn()
    render(<DiffViewer diff={binaryDiff} onClose={onClose} />)

    expect(screen.getByText('image.png')).toBeInTheDocument()
  })
})
