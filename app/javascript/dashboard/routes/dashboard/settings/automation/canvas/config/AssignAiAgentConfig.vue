<script setup>
// Editor de `assign_ai_agent` (enterprise). action_params = [assistant_id]. Lista os
// assistentes Captain da conta (captainAssistants/getRecords, carregado no FlowCanvasView).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();
const aiAgents = useMapGetter('captainAssistants/getRecords');

const options = computed(() =>
  aiAgents.value.map(agent => ({ id: agent.id, name: agent.name }))
);

const selected = computed({
  get() {
    const current = props.node.action_params?.[0];
    if (current === undefined || current === null || current === '')
      return null;
    return (
      options.value.find(opt => String(opt.id) === String(current)) || null
    );
  },
  set(value) {
    emit('update', { action_params: value ? [value.id] : [] });
  },
});
</script>

<template>
  <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.ASSIGN_AI_AGENT.LABEL')">
    <SingleSelect
      v-model="selected"
      :options="options"
      :placeholder="t('AUTOMATION.CANVAS.CONFIG.ASSIGN_AI_AGENT.PLACEHOLDER')"
    />
  </ConfigField>
</template>
