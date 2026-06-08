<script setup>
// Composer inline "+ Adicionar card" no final de cada coluna (P1-05).
// Pattern Trello. Sem modal. Enter cria, Esc cancela, foco volta ao input
// pra criação contínua.
//
// Backend: usa endpoint quick_create do kanban_items. Tenta match de contato
// por telefone (BrazilianPhoneNormalizer); se não acha, abre fluxo de
// "criar contato + conversa" (delegado ao componente pai via evento
// `request-new-contact` quando ainda não houver match — fallback).
//
// Por enquanto (MVP) chamamos uma action Vuex `kanban/quickCreateItem` que
// será adicionada quando o backend estiver pronto. Em falha exibimos
// snackbar com fallback.
import { ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useKanbanSnackbar } from 'dashboard/composables/kanban/useKanbanSnackbar';

const props = defineProps({
  funnelId: { type: Number, required: true },
  stageId: { type: Number, required: true },
  stageName: { type: String, default: '' },
});
const emit = defineEmits(['created']);

const { t } = useI18n();
const store = useStore();
const snackbar = useKanbanSnackbar();

const isOpen = ref(false);
const text = ref('');
const inputRef = ref(null);
const isSubmitting = ref(false);

const open = async () => {
  isOpen.value = true;
  await nextTick();
  inputRef.value?.focus();
};

const close = () => {
  isOpen.value = false;
  text.value = '';
};

const submit = async () => {
  const value = (text.value || '').trim();
  if (!value || isSubmitting.value) return;
  isSubmitting.value = true;
  try {
    const result = await store.dispatch('kanban/quickCreateItem', {
      funnelId: props.funnelId,
      stageId: props.stageId,
      contactQuery: value,
    });
    emit('created', result);
    snackbar.show({
      message: t('KANBAN.SNACKBAR.CARD_CREATED', { stage: props.stageName }),
      timeout: 3000,
      variant: 'success',
    });
    text.value = '';
    await nextTick();
    inputRef.value?.focus();
  } catch (e) {
    snackbar.show({
      message: t('KANBAN.COMPOSER.GENERIC_ERROR'),
      timeout: 4000,
      variant: 'error',
    });
  } finally {
    isSubmitting.value = false;
  }
};

defineExpose({ open, close });
</script>

<template>
  <div class="px-2 py-2">
    <button
      v-if="!isOpen"
      type="button"
      class="w-full flex items-center justify-center gap-1.5 px-3 h-9 rounded-lg text-sm text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors border border-dashed border-slate-200 dark:border-slate-700"
      :aria-label="t('KANBAN.COMPOSER.ADD_CARD_ARIA', { stage: stageName })"
      @click="open"
    >
      <Icon icon="i-lucide-plus" class="size-4" />
      {{ t('KANBAN.COMPOSER.ADD_CARD') }}
    </button>

    <div
      v-else
      class="rounded-lg border border-iris-300 dark:border-iris-700 bg-white dark:bg-slate-900 p-2 flex flex-col gap-2"
    >
      <textarea
        ref="inputRef"
        v-model="text"
        rows="2"
        class="w-full px-2 py-1 text-sm rounded-md bg-slate-50 dark:bg-slate-800 border border-transparent focus:border-iris-500 focus:outline-none resize-none text-slate-800 dark:text-slate-100"
        :placeholder="t('KANBAN.COMPOSER.PLACEHOLDER')"
        @keydown.enter.exact.prevent="submit"
        @keydown.escape.prevent="close"
      />
      <div class="flex items-center gap-2 justify-end">
        <button
          type="button"
          class="px-3 h-8 rounded-md text-xs font-medium text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
          @click="close"
        >
          {{ t('KANBAN.COMPOSER.CANCEL') }}
        </button>
        <button
          type="button"
          :disabled="!text.trim() || isSubmitting"
          class="px-3 h-8 rounded-md text-xs font-semibold bg-iris-600 text-white hover:bg-iris-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          @click="submit"
        >
          {{
            isSubmitting
              ? t('KANBAN.COMPOSER.CREATING')
              : t('KANBAN.COMPOSER.ADD')
          }}
        </button>
      </div>
    </div>
  </div>
</template>
