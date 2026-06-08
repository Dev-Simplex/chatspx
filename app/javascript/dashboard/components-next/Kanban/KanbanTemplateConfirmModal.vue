<script setup>
// KANBAN-P3-03: Modal que confirma envio de template após drop em stage
// que tem default_message_template_id. Variáveis editáveis com preview.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import KanbanAPI from 'dashboard/api/kanban';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useKanbanSnackbar } from 'dashboard/composables/kanban/useKanbanSnackbar';

const props = defineProps({
  open: { type: Boolean, default: false },
  funnelId: { type: [Number, String], default: null },
  itemId: { type: [Number, String], default: null },
  stage: { type: Object, default: () => ({}) },
  templatePreview: { type: String, default: '' },
  templateName: { type: String, default: '' },
  variables: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['close', 'sent']);

const { t } = useI18n();
const snackbar = useKanbanSnackbar();

const sending = ref(false);
const localVars = ref({ ...(props.variables || {}) });

watch(
  () => props.variables,
  v => {
    localVars.value = { ...(v || {}) };
  }
);

const renderedPreview = computed(() => {
  let text = props.templatePreview || '';
  Object.entries(localVars.value).forEach(([k, v]) => {
    text = text
      .replace(new RegExp(`\\{\\{\\s*${k}\\s*\\}\\}`, 'gi'), v || '')
      .replace(new RegExp(`\\{\\s*${k}\\s*\\}`, 'gi'), v || '');
  });
  return text;
});

const skip = () => emit('close', { sent: false });

const send = async () => {
  if (sending.value) return;
  sending.value = true;
  try {
    await KanbanAPI.sendTemplate(props.funnelId, props.itemId, {
      templateId:
        props.stage?.defaultMessageTemplateId ||
        props.stage?.default_message_template_id ||
        props.templateName,
      variables: localVars.value,
    });
    snackbar.show({
      message: t('KANBAN.TEMPLATE_SEND.SENT'),
      variant: 'success',
    });
    emit('sent', { variables: localVars.value });
    emit('close', { sent: true });
  } catch (e) {
    snackbar.show({
      message: e?.response?.data?.error || t('KANBAN.TEMPLATE_SEND.ERROR'),
      variant: 'error',
    });
  } finally {
    sending.value = false;
  }
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-[1000] flex items-center justify-center bg-black/40 p-4"
      @click.self="skip"
    >
      <div
        role="dialog"
        aria-modal="true"
        class="w-full max-w-md rounded-xl bg-white dark:bg-slate-900 shadow-2xl border border-slate-200 dark:border-slate-700"
      >
        <div
          class="flex items-start gap-3 border-b border-slate-200 dark:border-slate-800 px-5 py-4"
        >
          <div
            class="flex size-9 items-center justify-center rounded-lg bg-iris-100 text-iris-700 dark:bg-iris-900/40 dark:text-iris-300"
          >
            <Icon icon="i-lucide-send" class="size-4" />
          </div>
          <div class="flex-1">
            <h3 class="text-base font-semibold text-slate-900 dark:text-white">
              {{ t('KANBAN.TEMPLATE_SEND.TITLE') }}
            </h3>
            <p class="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
              {{
                t('KANBAN.TEMPLATE_SEND.SUBTITLE', {
                  stage: stage?.name || '',
                })
              }}
            </p>
          </div>
          <button
            type="button"
            class="inline-flex items-center justify-center size-7 rounded-md text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800"
            :aria-label="t('KANBAN.TEMPLATE_SEND.SKIP')"
            @click="skip"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>

        <div class="space-y-3 px-5 py-4">
          <div>
            <p
              class="mb-1 text-xs font-medium text-slate-500 dark:text-slate-400"
            >
              {{ t('KANBAN.TEMPLATE_SEND.PREVIEW_LABEL') }}
            </p>
            <div
              class="whitespace-pre-wrap rounded-lg bg-slate-50 dark:bg-slate-800 px-3 py-2 text-sm text-slate-800 dark:text-slate-100 border border-slate-200 dark:border-slate-700"
            >
              {{ renderedPreview || '—' }}
            </div>
          </div>
          <div v-if="Object.keys(localVars).length">
            <p
              class="mb-1 text-xs font-medium text-slate-500 dark:text-slate-400"
            >
              {{ t('KANBAN.TEMPLATE_SEND.EDIT_VARIABLES') }}
            </p>
            <div class="grid gap-2 sm:grid-cols-2">
              <label
                v-for="(value, name) in localVars"
                :key="name"
                class="flex flex-col gap-1"
              >
                <span
                  class="text-[11px] font-medium text-slate-500 dark:text-slate-400"
                >
                  {{ name }}
                </span>
                <input
                  v-model="localVars[name]"
                  type="text"
                  class="rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-iris-500"
                />
              </label>
            </div>
          </div>
        </div>

        <div
          class="flex items-center justify-end gap-2 border-t border-slate-200 dark:border-slate-800 px-5 py-3"
        >
          <button
            type="button"
            class="rounded-md px-3 py-1.5 text-sm font-medium text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800"
            @click="skip"
          >
            {{ t('KANBAN.TEMPLATE_SEND.SKIP') }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-1.5 rounded-md bg-iris-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-iris-700 disabled:opacity-60"
            :disabled="sending"
            @click="send"
          >
            <Icon
              v-if="sending"
              icon="i-lucide-loader-circle"
              class="size-3.5 animate-spin"
            />
            <Icon v-else icon="i-lucide-send" class="size-3.5" />
            {{ t('KANBAN.TEMPLATE_SEND.SEND_AND_MOVE') }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
