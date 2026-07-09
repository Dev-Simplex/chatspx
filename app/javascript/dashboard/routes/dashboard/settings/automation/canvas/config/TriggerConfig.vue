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
//   • 'webhook'  → um POST externo em `…/webhooks/flows/<token>` inicia o fluxo (trigger_type
//                  external_webhook). O TOKEN nasce no BACKEND ao salvar (Flow#ensure_webhook_token,
//                  backend-autoritativo) — o widget só EXIBE a URL read-only. O FlowCanvasView
//                  injeta `node.webhook_token` a partir de flow.trigger_config para display.
// A fonte da verdade é o nó na definition — o canvas faz o round-trip; trigger_config é só a
// projeção que o backend consome. TODO(F2): filtros do gatilho.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
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
  if (props.node.trigger_kind === 'webhook') return 'webhook';
  return 'event';
});

const kindOptions = computed(() => [
  { id: 'event', name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KIND_EVENT') },
  { id: 'keyword', name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KIND_KEYWORD') },
  { id: 'schedule', name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KIND_SCHEDULE') },
  { id: 'webhook', name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KIND_WEBHOOK') },
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

// --- Direção (entrada/saída/ambas) -----------------------------------------------
// Filtra o gatilho pela direção do evento: só ENTRADA (o contato inicia), só SAÍDA (um agente
// inicia) ou AMBAS (default). Resolve o bug clássico "ao criar conversa → atribuir ao time X"
// disparar quando o AGENTE abre a conversa (saída). Aplica-se aos gatilhos por evento e por
// palavra-chave. Persistido em node.direction; o backend lê de trigger_config.direction, com
// fallback ao próprio nó (ver automation_rule_listener#flow_trigger_direction). 'both' não filtra.
const showDirection = computed(
  () => kind.value === 'event' || kind.value === 'keyword'
);

const directionOptions = computed(() => [
  { id: 'both', name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.DIRECTION.BOTH') },
  {
    id: 'inbound',
    name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.DIRECTION.INBOUND'),
  },
  {
    id: 'outbound',
    name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.DIRECTION.OUTBOUND'),
  },
]);

const directionModel = computed({
  get() {
    const current = ['inbound', 'outbound'].includes(props.node.direction)
      ? props.node.direction
      : 'both';
    return (
      directionOptions.value.find(opt => opt.id === current) ||
      directionOptions.value[0]
    );
  },
  set(value) {
    emit('update', { direction: value?.id || 'both' });
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

// --- Modo webhook ----------------------------------------------------------------
// O token é backend-autoritativo e chega em node.webhook_token (injetado pelo FlowCanvasView a
// partir de flow.trigger_config). Vazio até o 1º save → mostramos "salve para gerar". O widget
// só EXIBE; nunca cria nem edita o token.
const webhookUrl = computed(() =>
  props.node.webhook_token
    ? `${window.location.origin}/webhooks/flows/${props.node.webhook_token}`
    : ''
);

const copyWebhookUrl = () => {
  if (!webhookUrl.value) return;
  navigator.clipboard?.writeText(webhookUrl.value);
  useAlert(t('AUTOMATION.CANVAS.CONFIG.TRIGGER.WEBHOOK.COPIED'));
};
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

    <template v-else-if="kind === 'webhook'">
      <ConfigField
        :label="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.WEBHOOK.URL_LABEL')"
        :hint="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.WEBHOOK.HINT')"
      >
        <div v-if="webhookUrl" class="flex items-center gap-2">
          <input
            :value="webhookUrl"
            readonly
            class="flex-1 px-3 py-2 font-mono text-xs rounded-lg outline outline-1 reset-base text-n-slate-12 bg-n-alpha-1 outline-n-weak dark:outline-n-strong"
            data-testid="config-trigger-webhook-url"
            @focus="event => event.target.select()"
          />
          <button
            type="button"
            class="flex items-center justify-center rounded-lg shrink-0 size-9 text-n-slate-11 bg-n-alpha-1 outline outline-1 outline-n-weak dark:outline-n-strong hover:text-n-slate-12"
            :title="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.WEBHOOK.COPY')"
            data-testid="config-trigger-webhook-copy"
            @click="copyWebhookUrl"
          >
            <span class="i-lucide-copy" />
          </button>
        </div>
        <p v-else class="text-sm text-n-slate-10">
          {{ t('AUTOMATION.CANVAS.CONFIG.TRIGGER.WEBHOOK.SAVE_FIRST') }}
        </p>
      </ConfigField>
    </template>

    <ConfigField
      v-if="showDirection"
      :label="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.DIRECTION.LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.DIRECTION.HINT')"
    >
      <SingleSelect
        v-model="directionModel"
        disable-search
        disable-deselect
        :options="directionOptions"
        data-testid="config-trigger-direction"
      />
    </ConfigField>
  </div>
</template>
