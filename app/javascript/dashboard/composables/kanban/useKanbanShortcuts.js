// Atalhos de teclado para o Kanban (P1-12).
// Comandos: n (novo card), c (novo funil), ? (mostrar ajuda), Esc (fechar).
// Setas são tratadas via foco nativo dos cards.
//
// Não dispara quando o foco está em input/textarea/contenteditable.
import { onMounted, onBeforeUnmount } from 'vue';

const isTextEntry = el => {
  if (!el) return false;
  const tag = el.tagName?.toLowerCase();
  if (tag === 'input' || tag === 'textarea' || tag === 'select') return true;
  return el.isContentEditable === true;
};

export function useKanbanShortcuts(handlers = {}) {
  const onKey = e => {
    if (isTextEntry(document.activeElement)) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const key = e.key;

    switch (key) {
      case 'n':
      case 'N':
        e.preventDefault();
        handlers.onNewCard?.();
        break;
      case 'c':
      case 'C':
        e.preventDefault();
        handlers.onNewFunnel?.();
        break;
      case '?':
        e.preventDefault();
        handlers.onHelp?.();
        break;
      case 'Escape':
        handlers.onEsc?.();
        break;
      default:
        break;
    }
  };

  onMounted(() => document.addEventListener('keydown', onKey));
  onBeforeUnmount(() => document.removeEventListener('keydown', onKey));
}
