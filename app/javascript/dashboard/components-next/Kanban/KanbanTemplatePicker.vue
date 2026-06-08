<script setup>
// KANBAN-P2-01: galeria de templates pré-prontos pt-BR.
// 6 cards visuais (vendas-whatsapp + suporte + onboarding + imobiliaria + ecommerce + clinica)
// + opção "Em branco". Clica → preview com etapas + botão "Usar este modelo".
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useKanbanTemplatesStore } from 'dashboard/store/pinia/kanban/templates';
import { useAlert } from 'dashboard/composables';

defineProps({
  show: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'applied', 'blank']);

const { t } = useI18n();
const templatesStore = useKanbanTemplatesStore();
const { templates, isFetching, isApplying } = storeToRefs(templatesStore);

const selected = ref(null);
const customName = ref('');

const sortedTemplates = computed(() => {
  // vendas-whatsapp em destaque (primeiro)
  const list = [...templates.value];
  return list.sort((a, b) => {
    if (a.slug === 'vendas-whatsapp') return -1;
    if (b.slug === 'vendas-whatsapp') return 1;
    return (a.vertical || '').localeCompare(b.vertical || '');
  });
});

const selectTemplate = tpl => {
  selected.value = tpl;
  customName.value = tpl?.name || '';
};

const back = () => {
  selected.value = null;
  customName.value = '';
};

const onClose = () => {
  selected.value = null;
  customName.value = '';
  emit('close');
};

const onBlank = () => {
  emit('blank');
  onClose();
};

const onApply = async () => {
  if (!selected.value) return;
  try {
    const kanban = await templatesStore.applyTemplate({
      templateId: selected.value.id,
      options: { name: customName.value || selected.value.name },
    });
    emit('applied', kanban);
    onClose();
  } catch (e) {
    useAlert(
      e?.response?.data?.error ||
        e?.message ||
        t('KANBAN.TEMPLATES.APPLY_ERROR')
    );
  }
};

onMounted(() => {
  if (!templates.value.length) templatesStore.fetchTemplates();
});
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 backdrop-blur-sm p-4"
    role="dialog"
    aria-modal="true"
    @click.self="onClose"
  >
    <div
      class="w-full max-w-3xl rounded-2xl bg-white dark:bg-slate-900 shadow-2xl flex flex-col max-h-[90vh]"
    >
      <header
        class="flex items-center justify-between gap-2 px-6 py-4 border-b border-slate-200 dark:border-slate-800"
      >
        <div class="min-w-0">
          <h2 class="text-lg font-semibold text-slate-900 dark:text-white">
            {{
              selected
                ? t('KANBAN.TEMPLATES.PREVIEW_TITLE', { name: selected.name })
                : t('KANBAN.TEMPLATES.GALLERY_TITLE')
            }}
          </h2>
          <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
            {{
              selected
                ? t('KANBAN.TEMPLATES.PREVIEW_SUBTITLE')
                : t('KANBAN.TEMPLATES.GALLERY_SUBTITLE')
            }}
          </p>
        </div>
        <button
          type="button"
          class="inline-flex items-center justify-center size-9 rounded-lg text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800"
          :aria-label="t('COMMON.CLOSE')"
          @click="onClose"
        >
          <Icon icon="i-lucide-x" class="size-5" />
        </button>
      </header>

      <!-- Galeria -->
      <section v-if="!selected" class="flex-1 overflow-y-auto px-6 py-4">
        <div
          v-if="isFetching && !templates.length"
          class="flex items-center justify-center py-12"
        >
          <Icon
            icon="i-lucide-loader-2"
            class="size-6 animate-spin text-slate-400"
          />
        </div>
        <div
          v-else
          class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3"
        >
          <button
            v-for="tpl in sortedTemplates"
            :key="tpl.id"
            type="button"
            class="text-left p-4 rounded-xl border border-slate-200 dark:border-slate-700 hover:border-iris-400 dark:hover:border-iris-500 bg-white dark:bg-slate-800/40 hover:shadow-md transition focus:outline-none focus:ring-2 focus:ring-iris-500"
            @click="selectTemplate(tpl)"
          >
            <div class="flex items-center gap-2 mb-2">
              <span
                class="inline-flex items-center justify-center size-9 rounded-lg"
                :style="{
                  background: `${tpl.color || '#94a3b8'}22`,
                  color: tpl.color || '#475569',
                }"
              >
                <Icon
                  :icon="tpl.icon || 'i-lucide-layout-grid'"
                  class="size-5"
                />
              </span>
              <h3 class="font-semibold text-sm text-slate-900 dark:text-white">
                {{ tpl.name }}
              </h3>
            </div>
            <p
              v-if="tpl.description"
              class="text-xs text-slate-500 dark:text-slate-400 line-clamp-2"
            >
              {{ tpl.description }}
            </p>
            <p
              class="mt-2 text-[11px] uppercase tracking-wide text-slate-400 dark:text-slate-500 font-medium"
            >
              {{
                t('KANBAN.TEMPLATES.STAGES_COUNT', {
                  count: (tpl.stagesConfig || []).length,
                })
              }}
            </p>
          </button>

          <button
            type="button"
            class="text-left p-4 rounded-xl border border-dashed border-slate-300 dark:border-slate-700 hover:border-iris-400 dark:hover:border-iris-500 bg-slate-50 dark:bg-slate-800/20 transition focus:outline-none focus:ring-2 focus:ring-iris-500"
            @click="onBlank"
          >
            <div class="flex items-center gap-2 mb-2">
              <span
                class="inline-flex items-center justify-center size-9 rounded-lg bg-slate-200 dark:bg-slate-700 text-slate-500"
              >
                <Icon icon="i-lucide-plus" class="size-5" />
              </span>
              <h3 class="font-semibold text-sm text-slate-900 dark:text-white">
                {{ t('KANBAN.TEMPLATES.BLANK_TITLE') }}
              </h3>
            </div>
            <p class="text-xs text-slate-500 dark:text-slate-400 line-clamp-2">
              {{ t('KANBAN.TEMPLATES.BLANK_DESCRIPTION') }}
            </p>
          </button>
        </div>
      </section>

      <!-- Preview -->
      <section v-else class="flex-1 overflow-y-auto px-6 py-4">
        <label
          class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
        >
          {{ t('KANBAN.TEMPLATES.NAME_LABEL') }}
        </label>
        <input
          v-model="customName"
          type="text"
          class="w-full px-3 h-10 mb-4 rounded-lg bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 text-sm text-slate-800 dark:text-slate-100 focus:border-iris-500 focus:outline-none"
          :placeholder="selected.name"
        />

        <h4
          class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400 mb-2"
        >
          {{ t('KANBAN.TEMPLATES.STAGES_TITLE') }}
        </h4>
        <ul class="space-y-1.5 mb-4">
          <li
            v-for="(stage, idx) in selected.stagesConfig || []"
            :key="`stage-${idx}`"
            class="flex items-center gap-2 px-3 py-2 rounded-lg bg-slate-50 dark:bg-slate-800/40"
          >
            <span
              class="size-2.5 rounded-full"
              :style="{ background: stage.color || '#94a3b8' }"
              aria-hidden="true"
            />
            <span
              class="text-sm font-medium text-slate-800 dark:text-slate-100"
            >
              {{ stage.name }}
            </span>
            <span
              v-if="stage.rot_after_days"
              class="ml-auto text-[10px] text-slate-500 dark:text-slate-400"
            >
              {{
                t('KANBAN.TEMPLATES.ROT_AFTER', { days: stage.rot_after_days })
              }}
            </span>
            <span
              v-if="stage.won_loss_type === 'won'"
              class="text-[10px] font-medium px-1.5 py-0.5 rounded-full bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300"
            >
              {{ t('KANBAN.TEMPLATES.WON_BADGE') }}
            </span>
            <span
              v-else-if="stage.won_loss_type === 'loss'"
              class="text-[10px] font-medium px-1.5 py-0.5 rounded-full bg-slate-200 text-slate-700 dark:bg-slate-700 dark:text-slate-200"
            >
              {{ t('KANBAN.TEMPLATES.LOSS_BADGE') }}
            </span>
          </li>
        </ul>
      </section>

      <footer
        class="flex items-center justify-between gap-2 px-6 py-3 border-t border-slate-200 dark:border-slate-800"
      >
        <button
          v-if="selected"
          type="button"
          class="text-sm text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white"
          @click="back"
        >
          {{ t('KANBAN.TEMPLATES.BACK') }}
        </button>
        <span v-else />
        <div class="flex items-center gap-2">
          <Button variant="ghost" size="sm" @click="onClose">
            {{ t('COMMON.CANCEL') }}
          </Button>
          <Button
            v-if="selected"
            variant="solid"
            size="sm"
            :is-loading="isApplying"
            :disabled="isApplying"
            @click="onApply"
          >
            {{ t('KANBAN.TEMPLATES.APPLY_BUTTON') }}
          </Button>
        </div>
      </footer>
    </div>
  </div>
</template>
