<script setup>
// KANBAN-P2-04: dropdown de vistas salvas (CRUD pessoal).
// "Salvar essa vista" lê filtros atuais + viewMode, persiste em kanban_views.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import KanbanConfirmDialog from './KanbanConfirmDialog.vue';
import { useKanbanViewsStore } from 'dashboard/store/pinia/kanban/views';
import { useKanbanFiltersStore } from 'dashboard/store/pinia/kanban/filters';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  funnelId: { type: [Number, String, null], default: null },
});
const emit = defineEmits(['applied']);

const { t } = useI18n();
const viewsStore = useKanbanViewsStore();
const filtersStore = useKanbanFiltersStore();
const { byKanban, isSaving } = storeToRefs(viewsStore);

const open = ref(false);
const savingMode = ref(false);
const newViewName = ref('');

const views = computed(() => byKanban.value[Number(props.funnelId)] || []);

const refresh = () => {
  if (props.funnelId) viewsStore.fetchViews(props.funnelId);
};

watch(() => props.funnelId, refresh);
onMounted(refresh);

const applyView = view => {
  if (!view) return;
  filtersStore.setFilters(view.filters || {});
  emit('applied', view);
  open.value = false;
};

const startSave = () => {
  savingMode.value = true;
  newViewName.value = '';
};

const cancelSave = () => {
  savingMode.value = false;
  newViewName.value = '';
};

const confirmSave = async () => {
  const name = newViewName.value.trim();
  if (!name || !props.funnelId) return;
  try {
    await viewsStore.createView({
      kanbanId: props.funnelId,
      name,
      filters: filtersStore.filters,
      settings: { viewMode: filtersStore.viewMode },
    });
    savingMode.value = false;
    newViewName.value = '';
  } catch (e) {
    const msg = e?.response?.data?.errors?.[0] || '';
    if (msg.startsWith('limit_reached:')) {
      useAlert(
        t('KANBAN.SAVED_VIEWS.MAX_REACHED', { max: msg.split(':')[1] || 50 })
      );
    } else {
      useAlert(t('KANBAN.SAVED_VIEWS.GENERIC_ERROR'));
    }
  }
};

const confirmDialog = ref({ open: false, view: null });

const requestRemoveView = view => {
  confirmDialog.value = { open: true, view };
};

const cancelRemoveView = () => {
  confirmDialog.value = { open: false, view: null };
};

const confirmRemoveView = async () => {
  const view = confirmDialog.value.view;
  confirmDialog.value = { open: false, view: null };
  if (!view) return;
  await viewsStore.deleteView({ kanbanId: props.funnelId, viewId: view.id });
  useAlert(t('KANBAN.SAVED_VIEWS.DELETED', { name: view.name }));
};
</script>

<template>
  <div class="relative">
    <button
      type="button"
      class="inline-flex items-center gap-1.5 px-3 h-9 rounded-lg text-sm font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
      :aria-label="t('KANBAN.SAVED_VIEWS.TITLE')"
      :title="t('KANBAN.SAVED_VIEWS.TITLE')"
      @click="open = !open"
    >
      <Icon icon="i-lucide-bookmark" class="size-4" />
      <span class="hidden sm:inline">{{ t('KANBAN.SAVED_VIEWS.TITLE') }}</span>
    </button>

    <div
      v-if="open"
      class="absolute right-0 top-10 z-30 w-72 rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 shadow-xl"
      @click.stop
    >
      <div class="px-3 py-2 border-b border-slate-100 dark:border-slate-800">
        <p
          class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400"
        >
          {{ t('KANBAN.SAVED_VIEWS.TITLE') }}
        </p>
      </div>
      <ul v-if="views.length" class="max-h-64 overflow-y-auto py-1">
        <li
          v-for="view in views"
          :key="view.id"
          class="flex items-center gap-2 px-3 py-2 hover:bg-slate-50 dark:hover:bg-slate-800 cursor-pointer"
          @click="applyView(view)"
        >
          <Icon icon="i-lucide-eye" class="size-4 text-slate-400" />
          <span
            class="flex-1 text-sm text-slate-800 dark:text-slate-100 truncate"
          >
            {{ view.name }}
          </span>
          <button
            type="button"
            class="size-7 inline-flex items-center justify-center rounded-md text-slate-400 hover:text-ruby-500 hover:bg-ruby-50 dark:hover:bg-ruby-900/30"
            :aria-label="t('KANBAN.SAVED_VIEWS.DELETE')"
            :title="t('KANBAN.SAVED_VIEWS.DELETE')"
            @click.stop="requestRemoveView(view)"
          >
            <Icon icon="i-lucide-trash-2" class="size-3.5" />
          </button>
        </li>
      </ul>
      <p v-else class="px-3 py-3 text-xs text-slate-500 dark:text-slate-400">
        {{ t('KANBAN.SAVED_VIEWS.EMPTY') }}
      </p>

      <div class="border-t border-slate-100 dark:border-slate-800 p-3">
        <template v-if="savingMode">
          <label
            class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
          >
            {{ t('KANBAN.SAVED_VIEWS.SAVE_TITLE') }}
          </label>
          <input
            v-model="newViewName"
            type="text"
            class="w-full px-2 h-8 rounded-md bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 text-sm text-slate-800 dark:text-slate-100 focus:border-iris-500 focus:outline-none mb-2"
            :placeholder="t('KANBAN.SAVED_VIEWS.SAVE_PLACEHOLDER')"
            maxlength="80"
            @keyup.enter="confirmSave"
          />
          <div class="flex items-center gap-2 justify-end">
            <button
              type="button"
              class="text-xs text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white"
              @click="cancelSave"
            >
              {{ t('COMMON.CANCEL') }}
            </button>
            <button
              type="button"
              class="px-2.5 h-8 rounded-md bg-iris-600 text-white text-xs font-medium hover:bg-iris-700 disabled:opacity-50"
              :disabled="!newViewName.trim() || isSaving"
              @click="confirmSave"
            >
              {{ t('KANBAN.SAVED_VIEWS.SAVE_CTA') }}
            </button>
          </div>
        </template>
        <button
          v-else
          type="button"
          class="w-full inline-flex items-center justify-center gap-1.5 px-2 h-8 rounded-md text-xs font-medium text-iris-600 hover:bg-iris-50 dark:hover:bg-iris-900/30"
          @click="startSave"
        >
          <Icon icon="i-lucide-plus" class="size-3.5" />
          {{ t('KANBAN.SAVED_VIEWS.SAVE_BUTTON') }}
        </button>
      </div>
    </div>

    <KanbanConfirmDialog
      :open="confirmDialog.open"
      :title="t('KANBAN.CONFIRM.DELETE_VIEW_TITLE')"
      :message="t('KANBAN.CONFIRM.DELETE_VIEW_BODY')"
      :confirm-label="t('KANBAN.CONFIRM.DELETE_CONFIRM_LABEL')"
      variant="destructive"
      @confirm="confirmRemoveView"
      @cancel="cancelRemoveView"
    />
  </div>
</template>
