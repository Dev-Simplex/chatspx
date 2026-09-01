import { onBeforeUnmount, onMounted } from 'vue';

/**
 * The three shortcuts the panel owns: invoke, accept, dismiss.
 *
 * Conflict audit done against the conversation screen before choosing them:
 *
 *   Ctrl/Cmd+J — free. `useChatListKeyboardEvents` binds Alt+J, the sidebar
 *     help modal binds `$mod+Slash`, the command bar binds `$mod+K`. Nothing
 *     else in the dashboard listens to `$mod+J`.
 *   Tab — the ReplyBox binds Tab to accept the ghost suggestion, but that
 *     handler lives inside the composer's ProseMirror keymap
 *     (`ReplyBox.vue:1250`). We only accept when the event originates inside
 *     the panel AND the caller says there is something to accept — otherwise
 *     Tab keeps moving focus (the panel itself cycles focus internally, see
 *     `handlePanelKeydown` in AIAssistantPanel).
 *   Esc — o painel deixou de ser um Dialog do Headless UI (correção C1), então
 *     fechar no Esc é responsabilidade do `onDismiss` do chamador: ele escala
 *     (parar de gerar → limpar erro → cancelar edição → limpar rascunho →
 *     fechar). Registramos na fase de CAPTURA para chegar antes do Esc da
 *     ConversationView, que navega de volta para o dashboard.
 *
 * @param {Object} params
 * @param {() => boolean} params.isOpen
 * @param {() => void} params.onToggle — Ctrl/Cmd+J
 * @param {() => boolean} params.onAccept — Tab; return true when consumed
 * @param {() => boolean} params.onDismiss — Esc; return true when consumed
 * @param {string} [params.panelSelector]
 */
export function useCopilotShortcuts({
  isOpen,
  onToggle,
  onAccept,
  onDismiss,
  panelSelector = '[data-ai-panel]',
}) {
  const isInsidePanel = event => {
    const target = event?.target;
    if (!target || typeof target.closest !== 'function') return false;
    return Boolean(target.closest(panelSelector));
  };

  function handleKeydown(event) {
    if (event.defaultPrevented || event.isComposing) return;

    const isModifier = event.ctrlKey || event.metaKey;
    if (isModifier && (event.key === 'j' || event.key === 'J')) {
      event.preventDefault();
      onToggle?.();
      return;
    }

    if (!isOpen?.()) return;

    if (event.key === 'Tab' && !event.shiftKey && !isModifier) {
      if (!isInsidePanel(event)) return;
      if (onAccept?.()) {
        event.preventDefault();
        event.stopPropagation();
      }
      return;
    }

    if (event.key === 'Escape') {
      if (onDismiss?.()) {
        event.preventDefault();
        event.stopPropagation();
      }
    }
  }

  onMounted(() => {
    window.addEventListener('keydown', handleKeydown, true);
  });

  onBeforeUnmount(() => {
    window.removeEventListener('keydown', handleKeydown, true);
  });

  return { handleKeydown };
}
