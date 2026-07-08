<script setup>
// Editor de `add_participant`. action_params = [user_id]. Adiciona um agente como PARTICIPANTE
// (seguidor) da conversa — não o responsável. Reusa a lista de agentes verificados
// (agents/getVerifiedAgents), a mesma do assign_agent, mas SEM a opção "self" (participante é
// sempre um agente concreto).
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
const agents = useMapGetter('agents/getVerifiedAgents');

const options = computed(() =>
  agents.value.map(agent => ({ id: agent.id, name: agent.name }))
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
  <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.ADD_PARTICIPANT.LABEL')">
    <SingleSelect
      v-model="selected"
      :options="options"
      :placeholder="t('AUTOMATION.CANVAS.CONFIG.ADD_PARTICIPANT.PLACEHOLDER')"
    />
  </ConfigField>
</template>
