<script setup>
// Editor do nó `trigger`: escolhe COMO o fluxo começa. Três modos (trigger_kind):
//   • 'event'    → um evento de conversa inicia o fluxo. Persistido em `node.event_name`;
//                  o FlowCanvasView o reflete em trigger_config.event_name (conversation_event).
//   • 'keyword'  → uma mensagem de contato cujo conteúdo casa com as palavras-chave inicia o
//                  fluxo. Persistido em `node.keywords` (lista) + `node.match` (exact|contains);
//                  vira trigger_config.{keywords,match} (trigger_type keyword) ao salvar.
//   • 'schedule' → o TEMPO inicia o fluxo (cron ou intervalo). Persistido em
//                  `node.schedule` = { mode, cron, every, unit }; vira trigger_config
//                  { mode, cron | every, unit } (trigger_type schedule). O Flows::ScheduleTriggerJob
//                  o lê a cada 15 min. Um schedule só age sobre conversas quando o flow tem
//                  condições de alvo (ver o job) — TODO(F3): editor de condições/alvo aqui.
// A fonte da verdade é o nó na definition — o canvas faz o round-trip; trigger_config é só a
// projeção que o backend consome. TODO(F2): filtros do gatilho e gatilho de webhook externo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { AUTOMATION_RULE_EVENTS } from 'dashboard/routes/dashboard/settings/automation/constants';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

// Nós de gatilho antigos não têm trigger_kind — tratamos como 'event' (retrocompatível).
const kind = computed(() => {
  if (props.node.trigger_kind === 'keyword') return 'keyword';
  if (props.node.trigger_kind === 'schedule') return 'schedule';
  return 'event';
});

const kindOptions = computed(() => [
  { id: 'event', name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KIND_EVENT') },
  { id: 'keyword', name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KIND_KEYWORD') },
  { id: 'schedule', name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KIND_SCHEDULE') },
]);

const kindModel = computed({
  get() {
    return (
      kindOptions.value.find(opt => opt.id === kind.value) ||
      kindOptions.value[0]
    );
  },
  set(value) {
    emit('update', { trigger_kind: value?.id || 'event' });
  },
});

// --- Modo evento -----------------------------------------------------------------
const eventOptions = computed(() =>
  AUTOMATION_RULE_EVENTS.map(event => ({
    id: event.key,
    name: t(`AUTOMATION.EVENTS.${event.value}`),
  }))
);

const selectedEvent = computed({
  get() {
    return (
      eventOptions.value.find(opt => opt.id === props.node.event_name) || null
    );
  },
  set(value) {
    emit('update', { event_name: value ? value.id : null });
  },
});

// --- Modo keyword ----------------------------------------------------------------
const matchOptions = computed(() => [
  {
    id: 'contains',
    name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KEYWORD.MATCH_CONTAINS'),
  },
  {
    id: 'exact',
    name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KEYWORD.MATCH_EXACT'),
  },
]);

const matchModel = computed({
  get() {
    const current = props.node.match === 'exact' ? 'exact' : 'contains';
    return (
      matchOptions.value.find(opt => opt.id === current) ||
      matchOptions.value[0]
    );
  },
  set(value) {
    emit('update', { match: value?.id === 'exact' ? 'exact' : 'contains' });
  },
});

// Uma keyword por linha. Guardamos como array em node.keywords; a textarea só formata.
const keywordsText = computed({
  get() {
    return Array.isArray(props.node.keywords)
      ? props.node.keywords.join('\n')
      : '';
  },
  set(value) {
    const keywords = String(value)
      .split('\n')
      .map(line => line.trim())
      .filter(Boolean);
    emit('update', { keywords });
  },
});

// --- Modo schedule ---------------------------------------------------------------
// node.schedule = { mode: 'cron'|'interval', cron, every, unit }. Espelha node.wait do WaitConfig.
const SCHEDULE_DEFAULTS = {
  mode: 'cron',
  cron: '0 9 * * 1',
  every: 1,
  unit: 'days',
};

const schedule = computed(() => ({
  ...SCHEDULE_DEFAULTS,
  ...(props.node.schedule || {}),
}));

const patchSchedule = partial => {
  emit('update', { schedule: { ...schedule.value, ...partial } });
};

const scheduleMode = computed(() =>
  schedule.value.mode === 'interval' ? 'interval' : 'cron'
);

const modeOptions = computed(() => [
  {
    id: 'cron',
    name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.MODE_CRON'),
  },
  {
    id: 'interval',
    name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.MODE_INTERVAL'),
  },
]);

const modeModel = computed({
  get() {
    return (
      modeOptions.value.find(opt => opt.id === scheduleMode.value) ||
      modeOptions.value[0]
    );
  },
  set(value) {
    patchSchedule({ mode: value?.id === 'interval' ? 'interval' : 'cron' });
  },
});

const cronModel = computed({
  get() {
    return schedule.value.cron;
  },
  set(value) {
    patchSchedule({ cron: String(value ?? '').trim() });
  },
});

const everyModel = computed({
  get() {
    return schedule.value.every;
  },
  set(value) {
    const parsed = Number.parseInt(value, 10);
    patchSchedule({ every: Number.isNaN(parsed) || parsed < 1 ? 1 : parsed });
  },
});

const unitOptions = computed(() => [
  {
    id: 'minutes',
    name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.UNIT_MINUTES'),
  },
  {
    id: 'hours',
    name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.UNIT_HOURS'),
  },
  {
    id: 'days',
    name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.UNIT_DAYS'),
  },
]);

const unitModel = computed({
  get() {
    return (
      unitOptions.value.find(opt => opt.id === schedule.value.unit) ||
      unitOptions.value[2]
    );
  },
  set(value) {
    patchSchedule({ unit: value?.id || 'days' });
  },
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KIND_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KIND_HINT')"
    >
      <SingleSelect
        v-model="kindModel"
        disable-search
        disable-deselect
        :options="kindOptions"
      />
    </ConfigField>

    <ConfigField
      v-if="kind === 'event'"
      :label="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.EVENT_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.EVENT_HINT')"
    >
      <SingleSelect
        v-model="selectedEvent"
        :options="eventOptions"
        :placeholder="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.EVENT_PLACEHOLDER')"
      />
    </ConfigField>

    <template v-else-if="kind === 'keyword'">
      <ConfigField
        :label="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KEYWORD.MATCH_LABEL')"
      >
        <SingleSelect
          v-model="matchModel"
          disable-search
          disable-deselect
          :options="matchOptions"
        />
      </ConfigField>
      <ConfigField
        :label="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KEYWORD.LIST_LABEL')"
        :hint="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KEYWORD.LIST_HINT')"
      >
        <textarea
          v-model="keywordsText"
          rows="5"
          class="w-full px-3 py-2 text-sm rounded-lg resize-y outline outline-1 text-n-slate-12 bg-n-alpha-1 outline-n-weak dark:outline-n-strong focus:outline-n-brand"
          :placeholder="
            t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KEYWORD.LIST_PLACEHOLDER')
          "
          data-testid="config-trigger-keywords"
        />
      </ConfigField>
    </template>

    <template v-else-if="kind === 'schedule'">
      <ConfigField
        :label="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.MODE_LABEL')"
        :hint="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.HINT')"
      >
        <SingleSelect
          v-model="modeModel"
          disable-search
          disable-deselect
          :options="modeOptions"
        />
      </ConfigField>

      <ConfigField
        v-if="scheduleMode === 'cron'"
        :label="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.CRON_LABEL')"
        :hint="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.CRON_HINT')"
      >
        <Input
          v-model="cronModel"
          size="sm"
          :placeholder="
            t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.CRON_PLACEHOLDER')
          "
          data-testid="config-trigger-cron"
        />
      </ConfigField>

      <template v-else>
        <ConfigField
          :label="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.EVERY_LABEL')"
        >
          <Input
            v-model="everyModel"
            type="number"
            size="sm"
            min="1"
            :placeholder="
              t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.EVERY_PLACEHOLDER')
            "
            data-testid="config-trigger-every"
          />
        </ConfigField>
        <ConfigField
          :label="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.SCHEDULE.UNIT_LABEL')"
        >
          <SingleSelect
            v-model="unitModel"
            disable-search
            disable-deselect
            :options="unitOptions"
          />
        </ConfigField>
      </template>
    </template>
  </div>
</template>
