<script setup>
// Editor do nó `trigger`: escolhe COMO o fluxo começa. Dois modos (trigger_kind):
//   • 'event'   → um evento de conversa inicia o fluxo. Persistido em `node.event_name`;
//                 o FlowCanvasView o reflete em trigger_config.event_name (conversation_event).
//   • 'keyword' → uma mensagem de contato cujo conteúdo casa com as palavras-chave inicia o
//                 fluxo. Persistido em `node.keywords` (lista) + `node.match` (exact|contains);
//                 vira trigger_config.{keywords,match} (trigger_type keyword) ao salvar.
// A fonte da verdade é o nó na definition — o canvas faz o round-trip; trigger_config é só a
// projeção que o backend consome. TODO(F2): gatilhos de schedule/webhook e filtros do gatilho.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
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
const kind = computed(() =>
  props.node.trigger_kind === 'keyword' ? 'keyword' : 'event'
);

const kindOptions = computed(() => [
  { id: 'event', name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KIND_EVENT') },
  { id: 'keyword', name: t('AUTOMATION.CANVAS.CONFIG.TRIGGER.KIND_KEYWORD') },
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

    <template v-else>
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
  </div>
</template>
