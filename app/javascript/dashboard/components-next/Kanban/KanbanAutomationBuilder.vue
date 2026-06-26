<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import KanbanAPI from 'dashboard/api/kanban';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  funnelId: { type: [Number, String], default: null },
});
const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();

const stages = computed(() =>
  store.getters['kanban/getFunnelStages'](props.funnelId)
);
const agents = computed(() => store.getters['agents/getAgents'] || []);

const dialogRef = ref(null);
const automations = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);

const blankDraft = () => ({
  name: '',
  event: 'item_entered_stage',
  hours: 24,
  funnel_stage_id: '',
  conditions: [],
  actions: [
    { type: 'tag', labels: '', stage_id: '', assignee_id: '', url: '' },
  ],
});
const draft = ref(blankDraft());

const load = async () => {
  automations.value = [];
  if (!props.funnelId) return;
  isLoading.value = true;
  try {
    const { data } = await KanbanAPI.getAutomations(props.funnelId);
    automations.value = Array.isArray(data) ? data : [];
  } catch (_) {
    // best effort
  } finally {
    isLoading.value = false;
  }
};
// O Dialog é um <dialog> nativo: precisa de .open()/.close() — montar não basta.
watch(
  () => [props.show, props.funnelId],
  async () => {
    if (props.show) {
      load();
      draft.value = blankDraft();
      await nextTick();
      dialogRef.value?.open?.();
    } else {
      dialogRef.value?.close?.();
    }
  },
  { immediate: true }
);

const stageName = id =>
  stages.value.find(s => Number(s.id) === Number(id))?.name;
const agentName = id =>
  agents.value.find(a => Number(a.id) === Number(id))?.name || `#${id}`;

const FIELD_OPTIONS = [
  'priority',
  'status',
  'assignee_id',
  'inbox_id',
  'labels',
];
const OP_OPTIONS = ['eq', 'neq', 'present', 'blank', 'includes'];
const ACTION_OPTIONS = ['move', 'assign', 'tag', 'webhook'];
const WEBHOOK_URL_PLACEHOLDER = 'https://';

const addCondition = () => {
  draft.value.conditions.push({ field: 'priority', op: 'eq', value: '' });
};
const removeCondition = i => draft.value.conditions.splice(i, 1);
const addAction = () => {
  draft.value.actions.push({
    type: 'tag',
    labels: '',
    stage_id: '',
    assignee_id: '',
    url: '',
  });
};
const removeAction = i => draft.value.actions.splice(i, 1);

// Turn the draft into the API payload shape.
const buildPayload = () => {
  const trigger =
    draft.value.event === 'time_in_stage'
      ? { event: 'time_in_stage', hours: Number(draft.value.hours) || 24 }
      : { event: 'item_entered_stage' };

  const actions = draft.value.actions
    .map(a => {
      if (a.type === 'move')
        return { type: 'move', stage_id: Number(a.stage_id) };
      if (a.type === 'assign') {
        return { type: 'assign', assignee_id: Number(a.assignee_id) };
      }
      if (a.type === 'tag') {
        return {
          type: 'tag',
          labels: String(a.labels)
            .split(',')
            .map(s => s.trim())
            .filter(Boolean),
        };
      }
      if (a.type === 'webhook') return { type: 'webhook', url: a.url };
      return null;
    })
    .filter(Boolean);

  return {
    name: draft.value.name.trim(),
    funnel_stage_id: draft.value.funnel_stage_id || null,
    trigger,
    conditions: draft.value.conditions
      .filter(c => c.field && c.op)
      .map(c => ({ field: c.field, op: c.op, value: c.value })),
    actions,
  };
};

const save = async () => {
  const payload = buildPayload();
  if (!payload.name || !payload.actions.length || isSaving.value) return;
  isSaving.value = true;
  try {
    const { data } = await KanbanAPI.createAutomation(props.funnelId, payload);
    automations.value = [...automations.value, data];
    draft.value = blankDraft();
  } catch (error) {
    const message =
      error?.response?.data?.errors?.join(', ') ||
      t('KANBAN.AUTOMATIONS.SAVE_ERROR');
    useAlert(message);
  } finally {
    isSaving.value = false;
  }
};

const remove = async automation => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('KANBAN.AUTOMATIONS.DELETE_CONFIRM', { name: automation.name })
    )
  )
    return;
  try {
    await KanbanAPI.deleteAutomation(props.funnelId, automation.id);
    automations.value = automations.value.filter(a => a.id !== automation.id);
  } catch (_) {
    useAlert(t('KANBAN.AUTOMATIONS.SAVE_ERROR'));
  }
};

// Human-readable one-liner for an existing automation.
const summarize = automation => {
  const ev =
    automation.trigger?.event === 'time_in_stage'
      ? t('KANBAN.AUTOMATIONS.WHEN_TIME', { hours: automation.trigger?.hours })
      : t('KANBAN.AUTOMATIONS.WHEN_ENTER');
  const acts = (automation.actions || [])
    .map(a => {
      if (a.type === 'move')
        return t('KANBAN.AUTOMATIONS.DO_MOVE', {
          stage: stageName(a.stage_id) || '?',
        });
      if (a.type === 'assign')
        return t('KANBAN.AUTOMATIONS.DO_ASSIGN', {
          agent: agentName(a.assignee_id),
        });
      if (a.type === 'tag')
        return t('KANBAN.AUTOMATIONS.DO_TAG', {
          labels: (a.labels || []).join(', '),
        });
      if (a.type === 'webhook') return t('KANBAN.AUTOMATIONS.DO_WEBHOOK');
      return a.type;
    })
    .join(' · ');
  return `${ev} → ${acts}`;
};

const close = () => emit('close');
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    position="center"
    overflow-y-auto
    :title="t('KANBAN.AUTOMATIONS.TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="close"
  >
    <p class="text-xs text-n-slate-10">
      {{ t('KANBAN.AUTOMATIONS.DESCRIPTION') }}
    </p>

    <!-- Existing rules -->
    <ul v-if="automations.length" class="mt-3 flex flex-col gap-1.5">
      <li
        v-for="automation in automations"
        :key="automation.id"
        class="group flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2"
      >
        <Icon
          :icon="automation.active ? 'i-lucide-zap' : 'i-lucide-zap-off'"
          class="size-4 shrink-0 text-n-amber-11"
        />
        <div class="min-w-0 flex-1">
          <p class="truncate text-sm font-medium text-n-slate-12">
            {{ automation.name }}
          </p>
          <p class="truncate text-[11px] text-n-slate-10">
            {{ summarize(automation) }}
          </p>
        </div>
        <button
          type="button"
          class="shrink-0 rounded p-1 text-n-ruby-11 opacity-0 transition hover:bg-n-ruby-3 group-hover:opacity-100"
          :title="t('KANBAN.AUTOMATIONS.DELETE')"
          @click="remove(automation)"
        >
          <Icon icon="i-lucide-trash-2" class="size-3.5" />
        </button>
      </li>
    </ul>
    <p v-else-if="!isLoading" class="mt-3 text-xs text-n-slate-10">
      {{ t('KANBAN.AUTOMATIONS.EMPTY') }}
    </p>

    <!-- New rule builder -->
    <div class="mt-4 rounded-lg border border-dashed border-n-weak p-3">
      <input
        v-model="draft.name"
        type="text"
        class="kanban-auto-input w-full"
        :placeholder="t('KANBAN.AUTOMATIONS.NAME_PLACEHOLDER')"
      />

      <!-- WHEN -->
      <div class="mt-3">
        <span class="kanban-auto-label">{{
          t('KANBAN.AUTOMATIONS.WHEN')
        }}</span>
        <div class="mt-1 flex flex-wrap items-center gap-2">
          <select v-model="draft.event" class="kanban-auto-input">
            <option value="item_entered_stage">
              {{ t('KANBAN.AUTOMATIONS.EV_ENTER') }}
            </option>
            <option value="time_in_stage">
              {{ t('KANBAN.AUTOMATIONS.EV_TIME') }}
            </option>
          </select>
          <template v-if="draft.event === 'time_in_stage'">
            <input
              v-model="draft.hours"
              type="number"
              min="1"
              class="kanban-auto-input w-20"
            />
            <span class="text-xs text-n-slate-10">{{
              t('KANBAN.AUTOMATIONS.HOURS')
            }}</span>
          </template>
          <select v-model="draft.funnel_stage_id" class="kanban-auto-input">
            <option value="">{{ t('KANBAN.AUTOMATIONS.ANY_STAGE') }}</option>
            <option v-for="stage in stages" :key="stage.id" :value="stage.id">
              {{ stage.name }}
            </option>
          </select>
        </div>
      </div>

      <!-- IF (conditions) -->
      <div class="mt-3">
        <span class="kanban-auto-label">{{ t('KANBAN.AUTOMATIONS.IF') }}</span>
        <div
          v-for="(cond, i) in draft.conditions"
          :key="i"
          class="mt-1 flex flex-wrap items-center gap-2"
        >
          <select v-model="cond.field" class="kanban-auto-input">
            <option v-for="f in FIELD_OPTIONS" :key="f" :value="f">
              {{ t(`KANBAN.AUTOMATIONS.FIELD.${f.toUpperCase()}`) }}
            </option>
          </select>
          <select v-model="cond.op" class="kanban-auto-input">
            <option v-for="o in OP_OPTIONS" :key="o" :value="o">
              {{ t(`KANBAN.AUTOMATIONS.OP.${o.toUpperCase()}`) }}
            </option>
          </select>
          <input
            v-if="cond.op !== 'present' && cond.op !== 'blank'"
            v-model="cond.value"
            type="text"
            class="kanban-auto-input flex-1"
            :placeholder="t('KANBAN.AUTOMATIONS.VALUE')"
          />
          <button
            type="button"
            class="text-n-ruby-11"
            @click="removeCondition(i)"
          >
            <Icon icon="i-lucide-x" class="size-3.5" />
          </button>
        </div>
        <Button
          size="sm"
          variant="ghost"
          icon="i-lucide-plus"
          class="mt-1"
          @click="addCondition"
        >
          <span class="ml-1">{{ t('KANBAN.AUTOMATIONS.ADD_CONDITION') }}</span>
        </Button>
      </div>

      <!-- THEN (actions) -->
      <div class="mt-3">
        <span class="kanban-auto-label">{{
          t('KANBAN.AUTOMATIONS.THEN')
        }}</span>
        <div
          v-for="(act, i) in draft.actions"
          :key="i"
          class="mt-1 flex flex-wrap items-center gap-2"
        >
          <select v-model="act.type" class="kanban-auto-input">
            <option v-for="a in ACTION_OPTIONS" :key="a" :value="a">
              {{ t(`KANBAN.AUTOMATIONS.ACT.${a.toUpperCase()}`) }}
            </option>
          </select>
          <select
            v-if="act.type === 'move'"
            v-model="act.stage_id"
            class="kanban-auto-input"
          >
            <option value="">{{ t('KANBAN.AUTOMATIONS.PICK_STAGE') }}</option>
            <option v-for="stage in stages" :key="stage.id" :value="stage.id">
              {{ stage.name }}
            </option>
          </select>
          <select
            v-else-if="act.type === 'assign'"
            v-model="act.assignee_id"
            class="kanban-auto-input"
          >
            <option value="">{{ t('KANBAN.AUTOMATIONS.PICK_AGENT') }}</option>
            <option v-for="agent in agents" :key="agent.id" :value="agent.id">
              {{ agent.name }}
            </option>
          </select>
          <input
            v-else-if="act.type === 'tag'"
            v-model="act.labels"
            type="text"
            class="kanban-auto-input flex-1"
            :placeholder="t('KANBAN.AUTOMATIONS.LABELS_PLACEHOLDER')"
          />
          <input
            v-else-if="act.type === 'webhook'"
            v-model="act.url"
            type="url"
            class="kanban-auto-input flex-1"
            :placeholder="WEBHOOK_URL_PLACEHOLDER"
          />
          <button type="button" class="text-n-ruby-11" @click="removeAction(i)">
            <Icon icon="i-lucide-x" class="size-3.5" />
          </button>
        </div>
        <Button
          size="sm"
          variant="ghost"
          icon="i-lucide-plus"
          class="mt-1"
          @click="addAction"
        >
          <span class="ml-1">{{ t('KANBAN.AUTOMATIONS.ADD_ACTION') }}</span>
        </Button>
      </div>

      <div class="mt-3 flex justify-end">
        <Button
          variant="primary"
          size="sm"
          :is-loading="isSaving"
          :disabled="!draft.name.trim()"
          @click="save"
        >
          {{ t('KANBAN.AUTOMATIONS.SAVE') }}
        </Button>
      </div>
    </div>
  </Dialog>
</template>

<style scoped>
.kanban-auto-label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--color-text-subtle, #64748b);
}
.kanban-auto-input {
  border-radius: 0.5rem;
  border: 1px solid var(--color-border-weak, rgba(0, 0, 0, 0.1));
  background-color: var(--color-background, #fff);
  padding: 0.3rem 0.5rem;
  font-size: 12px;
  line-height: 1.2;
  color: inherit;
}
.kanban-auto-input:focus {
  outline: none;
  border-color: var(--color-woot, #1f93ff);
}
</style>
