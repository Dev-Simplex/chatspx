<script setup>
// KANBAN-P2-06: modal Won/Lost com motivo estruturado.
// - Won: valor (cents), fonte, detalhe (opcional)
// - Lost: motivo OBRIGATÓRIO + tags sugeridas
// onSave dispara backend (KanbanAPI.markItemWon/Lost) e fecha;
// onSkip apenas fecha (estado já foi movido pelo store).
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import KanbanAPI from 'dashboard/api/kanban';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  show: { type: Boolean, default: false },
  mode: { type: String, default: 'won' }, // 'won' | 'lost'
  funnelId: { type: [Number, String, null], default: null },
  item: { type: Object, default: null },
});

const emit = defineEmits(['saved', 'skip']);

const { t } = useI18n();

const valueDisplay = ref('');
const source = ref('');
const detail = ref('');
const reason = ref('');
const selectedTags = ref([]);
const saving = ref(false);

const isLost = computed(() => props.mode === 'lost');

const tagOptions = computed(() => [
  { id: 'price', label: t('KANBAN.WON_LOST.TAG_PRICE') },
  { id: 'timing', label: t('KANBAN.WON_LOST.TAG_TIMING') },
  { id: 'competitor', label: t('KANBAN.WON_LOST.TAG_COMPETITOR') },
  { id: 'ghosted', label: t('KANBAN.WON_LOST.TAG_GHOSTED') },
  { id: 'budget', label: t('KANBAN.WON_LOST.TAG_BUDGET') },
  { id: 'other', label: t('KANBAN.WON_LOST.TAG_OTHER') },
]);

watch(
  () => props.show,
  open => {
    if (!open) return;
    valueDisplay.value = '';
    source.value = '';
    detail.value = '';
    reason.value = '';
    selectedTags.value = [];
  }
);

const toggleTag = id => {
  const idx = selectedTags.value.indexOf(id);
  if (idx === -1) selectedTags.value.push(id);
  else selectedTags.value.splice(idx, 1);
};

const parseValueCents = () => {
  const raw = String(valueDisplay.value)
    .replace(/[^\d,]/g, '')
    .replace(',', '.');
  const v = parseFloat(raw);
  return Number.isFinite(v) && v > 0 ? Math.round(v * 100) : null;
};

const canSubmit = computed(() => {
  if (saving.value) return false;
  if (isLost.value) return reason.value.trim().length > 0;
  return true;
});

const onSubmit = async () => {
  if (!props.item?.id || !props.funnelId) return;
  saving.value = true;
  try {
    if (isLost.value) {
      await KanbanAPI.markItemLost(props.funnelId, props.item.id, {
        reason: reason.value.trim(),
        tags: selectedTags.value,
      });
    } else {
      await KanbanAPI.markItemWon(props.funnelId, props.item.id, {
        reason: source.value || null,
        value_cents: parseValueCents(),
        source: source.value || null,
        detail: detail.value || null,
      });
    }
    emit('saved', { mode: props.mode });
  } catch (e) {
    useAlert(
      e?.response?.data?.error || e?.message || t('KANBAN.WON_LOST.SAVE_LOST')
    );
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 backdrop-blur-sm p-4"
    role="dialog"
    aria-modal="true"
    @click.self="emit('skip')"
  >
    <div
      class="w-full max-w-md rounded-2xl bg-white dark:bg-slate-900 shadow-2xl flex flex-col"
    >
      <header
        class="flex items-center justify-between gap-2 px-5 py-3 border-b border-slate-200 dark:border-slate-800"
      >
        <h2 class="text-base font-semibold text-slate-900 dark:text-white">
          {{
            isLost
              ? t('KANBAN.WON_LOST.LOST_TITLE')
              : t('KANBAN.WON_LOST.WON_TITLE')
          }}
        </h2>
        <button
          type="button"
          class="inline-flex items-center justify-center size-8 rounded-lg text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800"
          :aria-label="t('COMMON.CLOSE')"
          @click="emit('skip')"
        >
          <Icon icon="i-lucide-x" class="size-4" />
        </button>
      </header>

      <section class="px-5 py-4 flex flex-col gap-3">
        <template v-if="!isLost">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
            >
              {{ t('KANBAN.WON_LOST.VALUE_LABEL') }}
            </label>
            <input
              v-model="valueDisplay"
              type="text"
              inputmode="decimal"
              :placeholder="t('KANBAN.WON_LOST.VALUE_PLACEHOLDER')"
              class="w-full px-3 h-10 rounded-lg bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 text-sm text-slate-800 dark:text-slate-100 focus:border-iris-500 focus:outline-none"
            />
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
            >
              {{ t('KANBAN.WON_LOST.SOURCE_LABEL') }}
            </label>
            <input
              v-model="source"
              type="text"
              class="w-full px-3 h-10 rounded-lg bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 text-sm text-slate-800 dark:text-slate-100 focus:border-iris-500 focus:outline-none"
              :placeholder="t('KANBAN.WON_LOST.SOURCE_PLACEHOLDER')"
            />
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
            >
              {{ t('KANBAN.WON_LOST.DETAIL_LABEL') }}
            </label>
            <textarea
              v-model="detail"
              rows="2"
              class="w-full px-3 py-2 rounded-lg bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 text-sm text-slate-800 dark:text-slate-100 focus:border-iris-500 focus:outline-none"
            />
          </div>
        </template>

        <template v-else>
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
            >
              {{ t('KANBAN.WON_LOST.REASON_LABEL') }}
            </label>
            <textarea
              v-model="reason"
              rows="3"
              :placeholder="t('KANBAN.WON_LOST.REASON_PLACEHOLDER')"
              class="w-full px-3 py-2 rounded-lg bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 text-sm text-slate-800 dark:text-slate-100 focus:border-iris-500 focus:outline-none"
            />
          </div>

          <div>
            <p
              class="text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
            >
              {{ t('KANBAN.WON_LOST.TAGS_TITLE') }}
            </p>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="opt in tagOptions"
                :key="opt.id"
                type="button"
                class="px-2.5 py-1 rounded-full text-xs font-medium border transition-colors"
                :class="
                  selectedTags.includes(opt.id)
                    ? 'bg-iris-500 text-white border-iris-500'
                    : 'bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 border-slate-200 dark:border-slate-700 hover:border-iris-400'
                "
                @click="toggleTag(opt.id)"
              >
                {{ opt.label }}
              </button>
            </div>
          </div>
        </template>
      </section>

      <footer
        class="flex items-center justify-between gap-2 px-5 py-3 border-t border-slate-200 dark:border-slate-800"
      >
        <button
          type="button"
          class="text-xs text-slate-500 dark:text-slate-400 hover:text-slate-700 dark:hover:text-slate-200"
          @click="emit('skip')"
        >
          {{ t('KANBAN.WON_LOST.SKIP') }}
        </button>
        <Button
          variant="solid"
          size="sm"
          :is-loading="saving"
          :disabled="!canSubmit"
          @click="onSubmit"
        >
          {{
            isLost
              ? t('KANBAN.WON_LOST.SAVE_LOST')
              : t('KANBAN.WON_LOST.SAVE_WON')
          }}
        </Button>
      </footer>
    </div>
  </div>
</template>
