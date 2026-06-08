<script setup>
// KANBAN-P3-01: mini-composer in-card pra responder o cliente sem abrir conversa.
// - Textarea autoexpansiva (40 -> 120px), max 1024 chars
// - Atalho: Enter envia, Shift+Enter quebra linha, Esc cancela
// - Estados: idle | sending | sent | error
// - Falha 503 (canal offline) preserva texto e mostra retry
import { ref, computed, nextTick, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import KanbanAPI from 'dashboard/api/kanban';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useKanbanSnackbar } from 'dashboard/composables/kanban/useKanbanSnackbar';

const props = defineProps({
  funnelId: { type: [Number, String], required: true },
  itemId: { type: [Number, String], required: true },
  contactName: { type: String, default: '' },
});

const emit = defineEmits(['sent', 'close']);

const { t } = useI18n();
const snackbar = useKanbanSnackbar();

const textarea = ref(null);
const content = ref('');
const isPrivate = ref(false);
const status = ref('idle');
const errorMsg = ref('');

const MAX = 1024;
const remaining = computed(() => MAX - content.value.length);
const isFull = computed(() => content.value.length >= MAX);
const canSend = computed(
  () => content.value.trim().length > 0 && status.value !== 'sending'
);

const autoGrow = () => {
  const el = textarea.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight, 120)}px`;
};

const focusTextarea = async () => {
  await nextTick();
  textarea.value?.focus();
};

onMounted(focusTextarea);

const send = async () => {
  if (!canSend.value) return;
  status.value = 'sending';
  errorMsg.value = '';
  try {
    const { data } = await KanbanAPI.quickReply(props.funnelId, props.itemId, {
      content: content.value.trim(),
      isPrivate: isPrivate.value,
    });
    status.value = 'sent';
    snackbar.show({
      message: t('KANBAN.QUICK_REPLY.SENT'),
      variant: 'success',
      timeout: 3000,
    });
    emit('sent', data?.message);
    content.value = '';
    emit('close');
  } catch (e) {
    status.value = 'error';
    const isOffline = e?.response?.status === 503;
    errorMsg.value = isOffline
      ? t('KANBAN.QUICK_REPLY.ERROR_OFFLINE')
      : t('KANBAN.QUICK_REPLY.ERROR_GENERIC');
    snackbar.show({
      message: errorMsg.value,
      variant: 'error',
      timeout: 5000,
      action: { label: t('KANBAN.QUICK_REPLY.RETRY'), onClick: send },
    });
  }
};

const onKeydown = e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    send();
  } else if (e.key === 'Escape') {
    e.preventDefault();
    emit('close');
  } else if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
    e.preventDefault();
    send();
  }
};
</script>

<template>
  <div
    class="mt-2 flex flex-col gap-1.5 rounded-md border border-iris-200 bg-iris-50/40 p-2 dark:border-iris-800 dark:bg-iris-900/20"
    @click.stop
    @keydown.stop
  >
    <textarea
      ref="textarea"
      v-model="content"
      :maxlength="MAX"
      rows="2"
      :placeholder="
        t('KANBAN.QUICK_REPLY.PLACEHOLDER', {
          name: contactName || t('KANBAN.ITEMS.UNNAMED_CONTACT'),
        })
      "
      class="w-full resize-none rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-2 py-1.5 text-sm text-slate-900 dark:text-white placeholder-slate-400 focus:outline-none focus:ring-1 focus:ring-iris-500"
      @input="autoGrow"
      @keydown="onKeydown"
    />

    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2">
        <label
          class="flex cursor-pointer items-center gap-1 text-[11px] text-slate-500 dark:text-slate-400"
        >
          <input
            v-model="isPrivate"
            type="checkbox"
            class="size-3 rounded text-iris-600"
          />
          {{ t('KANBAN.QUICK_REPLY.PRIVATE_NOTE') }}
        </label>
        <span
          v-if="content.length"
          class="text-[10px]"
          :class="
            isFull
              ? 'text-ruby-600 font-medium'
              : remaining < 80
                ? 'text-amber-600'
                : 'text-slate-400'
          "
        >
          {{ content.length }}/{{ MAX }}
        </span>
      </div>

      <div class="flex items-center gap-1">
        <button
          type="button"
          class="inline-flex items-center justify-center rounded-md px-2 py-1 text-[11px] font-medium text-slate-600 dark:text-slate-300 hover:bg-slate-200/60 dark:hover:bg-slate-800"
          @click="emit('close')"
        >
          {{ t('KANBAN.QUICK_REPLY.CANCEL') }}
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md bg-iris-600 px-2.5 py-1 text-[11px] font-medium text-white hover:bg-iris-700 disabled:cursor-not-allowed disabled:opacity-60 transition-colors"
          :disabled="!canSend"
          :aria-label="t('KANBAN.QUICK_REPLY.SEND')"
          @click="send"
        >
          <Icon
            v-if="status === 'sending'"
            icon="i-lucide-loader-circle"
            class="size-3 animate-spin"
          />
          <Icon v-else icon="i-lucide-send" class="size-3" />
          {{ t('KANBAN.QUICK_REPLY.SEND') }}
        </button>
      </div>
    </div>

    <p
      v-if="errorMsg"
      class="text-[11px] text-ruby-600 dark:text-ruby-400 flex items-center gap-1"
    >
      <Icon icon="i-lucide-alert-triangle" class="size-3" />
      {{ errorMsg }}
    </p>
    <p class="hidden xl:block text-[10px] text-slate-400 dark:text-slate-500">
      {{ t('KANBAN.QUICK_REPLY.HINT') }}
    </p>
  </div>
</template>
