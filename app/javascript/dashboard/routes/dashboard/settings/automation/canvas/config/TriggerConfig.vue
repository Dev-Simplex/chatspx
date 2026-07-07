<script setup>
// Editor do nó `trigger` (config mínima da F1): o evento que inicia o fluxo. Persistido em
// `node.event_name`; o FlowCanvasView reflete isso em `trigger_config.event_name` ao salvar.
// TODO(F2): gatilhos de schedule/keyword/webhook e filtros do gatilho.
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

const options = computed(() =>
  AUTOMATION_RULE_EVENTS.map(event => ({
    id: event.key,
    name: t(`AUTOMATION.EVENTS.${event.value}`),
  }))
);

const selected = computed({
  get() {
    return options.value.find(opt => opt.id === props.node.event_name) || null;
  },
  set(value) {
    emit('update', { event_name: value ? value.id : null });
  },
});
</script>

<template>
  <ConfigField
    :label="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.EVENT_LABEL')"
    :hint="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.EVENT_HINT')"
  >
    <SingleSelect
      v-model="selected"
      :options="options"
      :placeholder="t('AUTOMATION.CANVAS.CONFIG.TRIGGER.EVENT_PLACEHOLDER')"
    />
  </ConfigField>
</template>
