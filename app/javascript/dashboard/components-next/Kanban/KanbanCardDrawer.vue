<script setup>
// KANBAN-P2-03: drawer lateral 480px com preview da conversa do card.
// Aceita Esc, click-fora e botão de fechar. Mobile = full-screen.
//
// Reaproveita MessagesView via fallback de link "abrir conversa completa"
// quando o componente não pode ser instanciado isoladamente — em vez de
// embutir, mostramos cabeçalho + últimas mensagens carregadas no Vuex.
import { computed, watch, ref, onMounted, onUnmounted, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  show: { type: Boolean, default: false },
  conversationId: { type: [Number, String, null], default: null },
});

const emit = defineEmits(['close']);

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const getConversationById = useMapGetter('conversations/getConversationById');
const drawerRef = ref(null);
const isLoading = ref(false);

const conversation = computed(() => {
  if (!props.conversationId) return null;
  const id = Number(props.conversationId);
  return getConversationById.value(id) || null;
});

const messages = computed(() => {
  const list = conversation.value?.messages || [];
  return list.slice(-30);
});

const contact = computed(() => {
  const c = conversation.value;
  return c?.contact || c?.meta?.sender || null;
});

const fetchMessages = async () => {
  if (!props.conversationId) return;
  isLoading.value = true;
  try {
    await store.dispatch(
      'setActiveChat',
      conversation.value || { id: Number(props.conversationId) }
    );
    if (conversation.value?.id) {
      await store.dispatch('fetchPreviousMessages', {
        conversationId: conversation.value.id,
      });
    }
  } catch (_) {
    /* swallow */
  } finally {
    isLoading.value = false;
  }
};

const onEsc = e => {
  if (props.show && e.key === 'Escape') emit('close');
};

const goFull = () => {
  const id =
    conversation.value?.displayId ||
    conversation.value?.display_id ||
    props.conversationId;
  if (!id) return;
  router.push({
    name: 'inbox_conversation',
    params: { conversation_id: id },
  });
  emit('close');
};

watch(
  () => props.show,
  async val => {
    if (val) {
      await nextTick();
      drawerRef.value?.focus?.();
      fetchMessages();
    }
  }
);

watch(() => props.conversationId, fetchMessages);

onMounted(() => window.addEventListener('keydown', onEsc));
onUnmounted(() => window.removeEventListener('keydown', onEsc));

const formatTime = ts => {
  if (!ts) return '';
  const d = typeof ts === 'number' ? new Date(ts * 1000) : new Date(ts);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
};

const isOutgoing = m => m?.message_type === 1 || m?.messageType === 'outgoing';
</script>

<template>
  <transition name="kanban-drawer">
    <div
      v-if="show"
      class="fixed inset-0 z-40 flex"
      role="dialog"
      aria-modal="true"
    >
      <div
        class="flex-1 bg-slate-900/30 backdrop-blur-[2px]"
        @click="emit('close')"
      />
      <aside
        ref="drawerRef"
        tabindex="-1"
        class="w-full sm:w-[480px] h-full bg-white dark:bg-slate-900 shadow-2xl flex flex-col"
      >
        <header
          class="flex items-center gap-3 px-4 py-3 border-b border-slate-200 dark:border-slate-800"
        >
          <Avatar
            :name="contact?.name || '—'"
            :src="contact?.thumbnail || contact?.avatar_url"
            :size="36"
            rounded-full
          />
          <div class="flex-1 min-w-0">
            <h3 class="font-semibold text-slate-900 dark:text-white truncate">
              {{ contact?.name || t('KANBAN.DRAWER.UNAVAILABLE') }}
            </h3>
            <p
              v-if="contact?.phone_number"
              class="text-xs text-slate-500 dark:text-slate-400 truncate"
            >
              {{ contact.phone_number }}
            </p>
          </div>
          <Button
            size="sm"
            variant="ghost"
            icon="i-lucide-external-link"
            :aria-label="t('KANBAN.DRAWER.OPEN_FULL')"
            :title="t('KANBAN.DRAWER.OPEN_FULL')"
            @click="goFull"
          />
          <button
            type="button"
            class="inline-flex items-center justify-center size-9 rounded-lg text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800"
            :aria-label="t('KANBAN.DRAWER.CLOSE')"
            @click="emit('close')"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </header>

        <section class="flex-1 overflow-y-auto px-4 py-3">
          <p
            v-if="isLoading && !messages.length"
            class="text-center text-xs text-slate-500 py-6"
          >
            {{ t('KANBAN.DRAWER.LOADING') }}
          </p>
          <p
            v-else-if="!messages.length"
            class="text-center text-xs text-slate-500 py-6"
          >
            {{ t('KANBAN.DRAWER.UNAVAILABLE') }}
          </p>
          <ul v-else class="space-y-2">
            <li
              v-for="m in messages"
              :key="m.id"
              class="flex"
              :class="isOutgoing(m) ? 'justify-end' : 'justify-start'"
            >
              <div
                class="max-w-[80%] rounded-2xl px-3 py-2 text-sm leading-snug shadow-sm"
                :class="
                  isOutgoing(m)
                    ? 'bg-iris-100 text-slate-900 dark:bg-iris-900/40 dark:text-slate-100'
                    : 'bg-slate-100 text-slate-800 dark:bg-slate-800 dark:text-slate-100'
                "
              >
                <p class="whitespace-pre-wrap break-words">
                  {{ m.content || m.processed_message_content }}
                </p>
                <p class="text-[10px] text-slate-500 mt-1">
                  {{ formatTime(m.created_at || m.createdAt) }}
                </p>
              </div>
            </li>
          </ul>
        </section>

        <footer
          class="px-4 py-3 border-t border-slate-200 dark:border-slate-800"
        >
          <Button
            variant="solid"
            size="sm"
            class="w-full"
            icon="i-lucide-external-link"
            @click="goFull"
          >
            {{ t('KANBAN.DRAWER.OPEN_FULL') }}
          </Button>
        </footer>
      </aside>
    </div>
  </transition>
</template>

<style scoped>
/* P1/P2 use Tailwind. Scoped só pra transição. */
.kanban-drawer-enter-active,
.kanban-drawer-leave-active {
  transition: opacity 180ms ease;
}
.kanban-drawer-enter-from,
.kanban-drawer-leave-to {
  opacity: 0;
}
</style>
