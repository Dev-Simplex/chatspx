import { computed, watchEffect } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const BASE_TITLE = 'SPX - CHAT';
const MAX_DISPLAY = 99;

/**
 * Mantém o `<title>` da aba do browser atualizado com o número de
 * notificações pendentes — pattern WhatsApp Web `(N) SPX - CHAT`.
 *
 * Conta APENAS `notifications/getUnreadCount` — assim o número
 * bate exatamente com o que o user vê em `/notifications` ao clicar.
 * Conversas atribuídas atrasadas têm seu próprio destaque visual
 * (ConversationCard urgency) — não duplicamos no title.
 *
 * Cap em "(99+)" pra evitar título gigante.
 * Inicializar uma única vez (em App.vue) — title é global.
 */
export function useDocumentTitle() {
  const unreadNotifs = useMapGetter('notifications/getUnreadCount');

  const totalCount = computed(() => Number(unreadNotifs.value) || 0);

  const displayCount = computed(() => {
    if (totalCount.value <= 0) return null;
    if (totalCount.value > MAX_DISPLAY) return `${MAX_DISPLAY}+`;
    return String(totalCount.value);
  });

  watchEffect(() => {
    if (typeof document === 'undefined') return;
    document.title = displayCount.value
      ? `(${displayCount.value}) ${BASE_TITLE}`
      : BASE_TITLE;
  });
}
