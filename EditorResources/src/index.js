import { Editor } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import { Markdown } from 'tiptap-markdown';
import MarkdownIt from 'markdown-it';
import markdownItTaskLists from 'markdown-it-task-lists';
import TaskList from '@tiptap/extension-task-list';
import TaskItem from '@tiptap/extension-task-item';
import Link from '@tiptap/extension-link';
import { Extension } from '@tiptap/core';
import { sinkListItem, liftListItem } from 'prosemirror-schema-list';

// ── Cleanup any previous editor instances (hot‑reload safe) ────────────
if (window.tiptapEditor) {
  window.tiptapEditor.destroy();
} else if (window.editor) {
  // legacy global from an older bundle
  window.editor.destroy?.();
}
document.querySelectorAll('.ProseMirror').forEach(el => el.remove());
// ──────────────────────────────────────────────────────────────────────

// ── Tab / Shift‑Tab indent behaviour for task‑list items ───────────
const TaskIndentKeys = Extension.create({
  name: 'taskIndentKeys',
  addKeyboardShortcuts() {
    return {
      Tab: ({ editor }) => {
        const { state, dispatch } = editor.view;
        const { taskItem } = state.schema.nodes;
        // attempt to indent; return whether it succeeded
        return sinkListItem(taskItem)(state, dispatch);
      },
      'Shift-Tab': ({ editor }) => {
        const { state, dispatch } = editor.view;
        const { taskItem } = state.schema.nodes;
        // attempt to outdent; return whether it succeeded
        return liftListItem(taskItem)(state, dispatch);
      },
    };
  },
});
// ──────────────────────────────────────────────────────────────────

// ⬇️ index.html 에 있던 코드 그대로 복사
const editor = new Editor({
  element: document.querySelector('#editorRoot'),
    extensions: [
      // 기본 리스트 노드 비활성화 후 TaskList 사용
      StarterKit.configure({
        hardBreak: false,
      }),
      Link.configure({
        autolink: true,
        linkOnPaste: true,
        openOnClick: false,   // we handle click in Swift
        HTMLAttributes: { target: '_blank', rel: 'noopener noreferrer' },
      }),
      TaskItem.configure({ nested: true }),
      TaskList,
      Markdown.configure({
              html: false,
              // Markdown-it 인스턴스에 taskList 플러그인 결합
              markdownit: () =>
                MarkdownIt({ html: false }).use(markdownItTaskLists),
            }),
      TaskIndentKeys,
    ]
});
window.tiptapEditor = editor;

window.editor = editor;                // temporary backward compatibility
console.log('[TipTap] editor initialised →', editor);

// ── Disable Tab focus on hidden <input type="checkbox"> to avoid WKWebView crash
const patchCheckboxTabIndex = view => {
  view.dom
    .querySelectorAll('input[type="checkbox"]')
    .forEach(cb => cb.setAttribute('tabindex', '-1'));
};
patchCheckboxTabIndex(editor.view);              // initial document
editor.on('update', () => patchCheckboxTabIndex(editor.view)); // future nodes
// ─────────────────────────────────────────────────────────────


// --- Custom paste: insert plain text exactly at cursor -----------------
editor.on('paste', event => {
  event.preventDefault();                                  // stop default paste
  const text = event.clipboardData?.getData('text/plain'); // plain‑text only
  if (text) {
    // Remove trailing newline (if any) to avoid creating extra paragraph
    const clean = text.replace(/\n$/, '');
    editor.commands.insertContent(clean);
  }
});
// ----------------------------------------------------------------------

// Swift ➜ JS
window.setMarkdown = md =>
  editor.commands.setMarkdown(md);

// JS ➜ Swift
window.getMarkdown = () =>
  editor.storage.markdown.getMarkdown();


// 업데이트 브릿지
editor.on('update', () => {
  window.webkit?.messageHandlers?.didChange?.postMessage(window.getMarkdown());
});

// ── Intercept link clicks and forward to Swift ───────────────
document.addEventListener('click', e => {
  const link = e.target.closest('a[href]');
  console.log('[JS] click capture →', link?.href);
  if (link && !link.href.startsWith('about:')) {
    e.preventDefault();
    window.webkit?.messageHandlers?.openLink?.postMessage(link.href);
  }
}, true);     // capture phase so TipTap can't stopPropagation
// ─────────────────────────────────────────────────────────────
