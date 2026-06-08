<script setup>
// KANBAN-P3-05: lista + cria/edita automations + receitas pré-prontas.
// Bem enxuto: lista vertical com cards, formulário inline (sem modal pra MVP).
import { ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import KanbanAPI from 'dashboard/api/kanban';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import KanbanConfirmDialog from './KanbanConfirmDialog.vue';
import { useKanbanSnackbar } from 'dashboard/composables/kanban/useKanbanSnackbar';

const props = defineProps({
  funnelId: { type: [Number, String], required: true },
  stages: { type: Array, default: () => [] },
});

const { t } = useI18n();
const snackbar = useKanbanSnackbar();

const automations = ref([]);
const recipes = ref([]);
const isLoading = ref(false);
const editing = ref(null);

const fetchAll = async () => {
  isLoading.value = true;
  try {
    const [a, r] = await Promise.all([
      KanbanAPI.listAutomations(props.funnelId),
      KanbanAPI.getAutomationRecipes(props.funnelId).catch(() => ({
        data: [],
      })),
    ]);
    automations.value = a.data || [];
    recipes.value = r.data || [];
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchAll);
watch(() => props.funnelId, fetchAll);

const startNew = () => {
  editing.value = {
    name: '',
    trigger: 'item_entered_stage',
    kanban_stage_id: null,
    conditions: { days: 5 },
    actions: [{ type: 'send_template', template_slug: '' }],
    enabled: true,
  };
};

const startFromRecipe = recipe => {
  const matchedStage = props.stages.find(s =>
    String(s.name || '')
      .toLowerCase()
      .includes(String(recipe.stage_match || '').replace('_', ' '))
  );
  editing.value = {
    name: recipe.name,
    trigger: recipe.trigger,
    kanban_stage_id: matchedStage?.id || null,
    conditions: recipe.conditions || {},
    actions: recipe.actions || [],
    enabled: true,
  };
};

const cancelEdit = () => {
  editing.value = null;
};

const save = async () => {
  try {
    if (editing.value.id) {
      const { data } = await KanbanAPI.updateAutomation(
        props.funnelId,
        editing.value.id,
        editing.value
      );
      const idx = automations.value.findIndex(a => a.id === data.id);
      if (idx >= 0) automations.value[idx] = data;
    } else {
      const { data } = await KanbanAPI.createAutomation(
        props.funnelId,
        editing.value
      );
      automations.value.unshift(data);
    }
    editing.value = null;
    snackbar.show({
      message: t('KANBAN.AUTOMATIONS.SAVE'),
      variant: 'success',
    });
  } catch (e) {
    snackbar.show({
      message: e?.response?.data?.errors?.[0] || 'Error',
      variant: 'error',
    });
  }
};

const toggleEnabled = async automation => {
  const next = !automation.enabled;
  try {
    const { data } = await KanbanAPI.updateAutomation(
      props.funnelId,
      automation.id,
      {
        enabled: next,
      }
    );
    const idx = automations.value.findIndex(a => a.id === data.id);
    if (idx >= 0) automations.value[idx] = data;
  } catch (e) {
    snackbar.show({ message: 'Error', variant: 'error' });
  }
};

const confirmDialog = ref({ open: false, automation: null });

const removeAutomation = automation => {
  confirmDialog.value = { open: true, automation };
};

const cancelRemoveAutomation = () => {
  confirmDialog.value = { open: false, automation: null };
};

const confirmRemoveAutomation = async () => {
  const automation = confirmDialog.value.automation;
  confirmDialog.value = { open: false, automation: null };
  if (!automation) return;
  try {
    await KanbanAPI.deleteAutomation(props.funnelId, automation.id);
    automations.value = automations.value.filter(a => a.id !== automation.id);
  } catch (e) {
    snackbar.show({ message: 'Error', variant: 'error' });
  }
};

const triggerLabel = trigger =>
  ({
    item_entered_stage: t('KANBAN.AUTOMATIONS.TRIGGER_ENTERED'),
    item_left_stage: t('KANBAN.AUTOMATIONS.TRIGGER_LEFT'),
    item_aging_threshold: t('KANBAN.AUTOMATIONS.TRIGGER_AGING'),
  })[trigger] || trigger;

const actionLabel = type =>
  ({
    send_template: t('KANBAN.AUTOMATIONS.ACTION_SEND_TEMPLATE'),
    assign: t('KANBAN.AUTOMATIONS.ACTION_ASSIGN'),
    add_label: t('KANBAN.AUTOMATIONS.ACTION_LABEL'),
    move: t('KANBAN.AUTOMATIONS.ACTION_MOVE'),
    create_task: t('KANBAN.AUTOMATIONS.ACTION_CREATE_TASK'),
  })[type] || type;
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4"
  >
    <header class="flex items-center justify-between gap-2">
      <div>
        <h3 class="text-base font-semibold text-slate-900 dark:text-white">
          {{ t('KANBAN.AUTOMATIONS.TITLE') }}
        </h3>
        <p class="text-xs text-slate-500 dark:text-slate-400">
          {{ t('KANBAN.AUTOMATIONS.DESCRIPTION') }}
        </p>
      </div>
      <button
        type="button"
        class="inline-flex items-center gap-1.5 rounded-md bg-iris-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-iris-700"
        @click="startNew"
      >
        <Icon icon="i-lucide-plus" class="size-3.5" />
        {{ t('KANBAN.AUTOMATIONS.NEW') }}
      </button>
    </header>

    <div v-if="recipes.length" class="flex flex-wrap gap-2">
      <button
        v-for="recipe in recipes"
        :key="recipe.slug"
        type="button"
        class="rounded-md border border-dashed border-slate-300 dark:border-slate-600 px-2 py-1 text-[11px] text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800"
        @click="startFromRecipe(recipe)"
      >
        + {{ recipe.name }}
      </button>
    </div>

    <div
      v-if="editing"
      class="rounded-lg border border-iris-200 dark:border-iris-800 bg-iris-50/40 dark:bg-iris-900/20 p-3 space-y-2"
    >
      <input
        v-model="editing.name"
        type="text"
        :placeholder="t('KANBAN.AUTOMATIONS.NEW')"
        class="w-full rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-2 py-1 text-sm"
      />
      <div class="flex flex-wrap gap-2 items-center">
        <label class="text-xs text-slate-600 dark:text-slate-300">
          {{ t('KANBAN.AUTOMATIONS.TRIGGER_LABEL') }}:
          <select
            v-model="editing.trigger"
            class="ml-1 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-1 py-0.5 text-xs"
          >
            <option value="item_entered_stage">
              {{ t('KANBAN.AUTOMATIONS.TRIGGER_ENTERED') }}
            </option>
            <option value="item_left_stage">
              {{ t('KANBAN.AUTOMATIONS.TRIGGER_LEFT') }}
            </option>
            <option value="item_aging_threshold">
              {{ t('KANBAN.AUTOMATIONS.TRIGGER_AGING') }}
            </option>
          </select>
        </label>
        <label class="text-xs text-slate-600 dark:text-slate-300">
          {{ t('KANBAN.AUTOMATIONS.STAGE_LABEL') }}:
          <select
            v-model="editing.kanban_stage_id"
            class="ml-1 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-1 py-0.5 text-xs"
          >
            <option :value="null">—</option>
            <option v-for="s in stages" :key="s.id" :value="s.id">
              {{ s.name }}
            </option>
          </select>
        </label>
        <label
          v-if="editing.trigger === 'item_aging_threshold'"
          class="text-xs text-slate-600 dark:text-slate-300"
        >
          {{ t('KANBAN.AUTOMATIONS.DAYS_LABEL') }}:
          <input
            v-model.number="editing.conditions.days"
            type="number"
            min="1"
            class="ml-1 w-16 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-1 py-0.5 text-xs"
          />
        </label>
      </div>
      <div class="flex justify-end gap-2">
        <button
          type="button"
          class="rounded-md px-2 py-1 text-xs text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800"
          @click="cancelEdit"
        >
          {{ t('KANBAN.AUTOMATIONS.CANCEL') }}
        </button>
        <button
          type="button"
          class="rounded-md bg-iris-600 px-2 py-1 text-xs font-medium text-white hover:bg-iris-700"
          @click="save"
        >
          {{ t('KANBAN.AUTOMATIONS.SAVE') }}
        </button>
      </div>
    </div>

    <ul v-if="!isLoading" class="space-y-2">
      <li
        v-if="!automations.length"
        class="text-xs text-slate-500 dark:text-slate-400"
      >
        {{ t('KANBAN.AUTOMATIONS.EMPTY') }}
      </li>
      <li
        v-for="automation in automations"
        :key="automation.id"
        class="flex items-start justify-between gap-3 rounded-lg border border-slate-200 dark:border-slate-700 px-3 py-2"
      >
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-slate-900 dark:text-white">
            {{ automation.name }}
          </p>
          <p class="text-[11px] text-slate-500 dark:text-slate-400">
            {{ triggerLabel(automation.trigger) }} ·
            <span v-for="(a, i) in automation.actions" :key="i">
              {{ actionLabel(a.type)
              }}<span v-if="i < automation.actions.length - 1">, </span>
            </span>
          </p>
        </div>
        <div class="flex items-center gap-1">
          <button
            type="button"
            class="rounded-md px-2 py-1 text-[11px]"
            :class="
              automation.enabled
                ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300'
                : 'bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400'
            "
            @click="toggleEnabled(automation)"
          >
            {{
              automation.enabled
                ? t('KANBAN.AUTOMATIONS.ENABLED')
                : t('KANBAN.AUTOMATIONS.DISABLED')
            }}
          </button>
          <button
            type="button"
            class="inline-flex items-center justify-center size-7 rounded-md text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800"
            :aria-label="t('KANBAN.AUTOMATIONS.DELETE')"
            @click="removeAutomation(automation)"
          >
            <Icon icon="i-lucide-trash" class="size-3.5" />
          </button>
        </div>
      </li>
    </ul>

    <KanbanConfirmDialog
      :open="confirmDialog.open"
      :title="t('KANBAN.CONFIRM.DELETE_AUTOMATION_TITLE')"
      :message="t('KANBAN.CONFIRM.DELETE_AUTOMATION_BODY')"
      :confirm-label="t('KANBAN.CONFIRM.DELETE_CONFIRM_LABEL')"
      variant="destructive"
      @confirm="confirmRemoveAutomation"
      @cancel="cancelRemoveAutomation"
    />
  </section>
</template>
