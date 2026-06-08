<script setup>
// KANBAN-P3-02: chip de sugestão Captain AI Triage no card.
// Mostra stage sugerido + confiança, com botões Aceitar/Descartar.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import KanbanAPI from 'dashboard/api/kanban';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useKanbanSnackbar } from 'dashboard/composables/kanban/useKanbanSnackbar';
import { useKanbanBoardStore } from 'dashboard/store/pinia/kanban/board';

const props = defineProps({
  item: { type: Object, required: true },
  funnelId: { type: [Number, String], required: true },
  stages: { type: Array, default: () => [] },
});

const { t } = useI18n();
const snackbar = useKanbanSnackbar();
const boardStore = useKanbanBoardStore();
const busy = ref(false);

const classification = computed(
  () => props.item?.metadata?.captain_classification || {}
);

const suggestedStage = computed(() => {
  const id = Number(
    classification.value?.stage_id || classification.value?.stageId || 0
  );
  if (!id) return null;
  return (
    boardStore.stageById(id) ||
    (props.stages || []).find(s => Number(s?.id) === id) ||
    null
  );
});

const confidence = computed(() => {
  const raw =
    classification.value?.confidence ?? classification.value?.score ?? 0;
  const pct = Number(raw) <= 1 ? Number(raw) * 100 : Number(raw);
  return Math.round(pct);
});

const isLowConfidence = computed(() => confidence.value < 60);
const isHighConfidence = computed(() => confidence.value >= 85);

const chipClasses = computed(() => {
  if (isHighConfidence.value)
    return 'bg-emerald-50 border-emerald-200 text-emerald-800 dark:bg-emerald-900/30 dark:border-emerald-800 dark:text-emerald-200';
  if (isLowConfidence.value)
    return 'bg-slate-50 border-slate-200 text-slate-700 dark:bg-slate-800 dark:border-slate-700 dark:text-slate-300';
  return 'bg-amber-50 border-amber-200 text-amber-800 dark:bg-amber-900/30 dark:border-amber-800 dark:text-amber-200';
});

const accept = async () => {
  if (busy.value) return;
  busy.value = true;
  try {
    await KanbanAPI.acceptSuggestion(props.funnelId, props.item.id);
    snackbar.show({
      message: t('KANBAN.SNACKBAR.CARD_MOVED', {
        stage: suggestedStage.value?.name || '',
      }),
      variant: 'success',
    });
  } catch (e) {
    snackbar.show({ message: e?.message || 'error', variant: 'error' });
  } finally {
    busy.value = false;
  }
};

const reject = async () => {
  if (busy.value) return;
  busy.value = true;
  try {
    await KanbanAPI.rejectSuggestion(props.funnelId, props.item.id);
  } catch (e) {
    // silent
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <div
    v-if="suggestedStage"
    class="mt-1.5 flex items-center gap-1.5 rounded-md border px-2 py-1 text-[11px]"
    :class="chipClasses"
  >
    <Icon icon="i-lucide-sparkles" class="size-3 flex-shrink-0" />
    <span class="min-w-0 flex-1 truncate">
      <span class="font-semibold">{{
        t('KANBAN.CAPTAIN.SUGGESTION_LINE', {
          stage: suggestedStage.name,
          value: confidence,
        })
      }}</span>
    </span>
    <button
      type="button"
      :disabled="busy"
      :aria-label="t('KANBAN.CAPTAIN.ACCEPT_ARIA')"
      :title="t('KANBAN.CAPTAIN.ACCEPT')"
      class="inline-flex items-center justify-center size-5 rounded text-emerald-600 hover:bg-emerald-100 dark:hover:bg-emerald-900/40 disabled:opacity-50 transition-colors"
      @click.stop="accept"
    >
      <Icon icon="i-lucide-thumbs-up" class="size-3" />
    </button>
    <button
      type="button"
      :disabled="busy"
      :aria-label="t('KANBAN.CAPTAIN.REJECT_ARIA')"
      :title="t('KANBAN.CAPTAIN.REJECT')"
      class="inline-flex items-center justify-center size-5 rounded text-slate-500 hover:bg-slate-200 dark:hover:bg-slate-700 disabled:opacity-50 transition-colors"
      @click.stop="reject"
    >
      <Icon icon="i-lucide-thumbs-down" class="size-3" />
    </button>
  </div>
</template>
