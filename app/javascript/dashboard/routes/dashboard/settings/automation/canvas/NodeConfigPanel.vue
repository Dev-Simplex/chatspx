<script setup>
// Dispatcher dos editores de nó: escolhe o SFC de configuração conforme o type/action_name
// do nó e repassa o patch de `update` para cima. Cada editor recebe `:node` e emite
// `update` com o pedaço da definition a alterar (action_params, conditions ou event_name).
import { computed, markRaw } from 'vue';
import TriggerConfig from './config/TriggerConfig.vue';
import ConditionConfig from './config/ConditionConfig.vue';
import RouterConfig from './config/RouterConfig.vue';
import MessageConfig from './config/MessageConfig.vue';
import SendTemplateConfig from './config/SendTemplateConfig.vue';
import SetAttributeConfig from './config/SetAttributeConfig.vue';
import MoveFunnelStageConfig from './config/MoveFunnelStageConfig.vue';
import CallMacroConfig from './config/CallMacroConfig.vue';
import AssignAgentConfig from './config/AssignAgentConfig.vue';
import AssignTeamConfig from './config/AssignTeamConfig.vue';
import AssignAiAgentConfig from './config/AssignAiAgentConfig.vue';
import LabelConfig from './config/LabelConfig.vue';
import ChangeStatusConfig from './config/ChangeStatusConfig.vue';
import ChangePriorityConfig from './config/ChangePriorityConfig.vue';
import WaitConfig from './config/WaitConfig.vue';
import GenericConfig from './config/GenericConfig.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const ACTION_EDITORS = {
  send_message: markRaw(MessageConfig),
  add_private_note: markRaw(MessageConfig),
  send_template: markRaw(SendTemplateConfig),
  set_attribute: markRaw(SetAttributeConfig),
  move_funnel_stage: markRaw(MoveFunnelStageConfig),
  call_macro: markRaw(CallMacroConfig),
  assign_agent: markRaw(AssignAgentConfig),
  assign_team: markRaw(AssignTeamConfig),
  assign_ai_agent: markRaw(AssignAiAgentConfig),
  add_label: markRaw(LabelConfig),
  remove_label: markRaw(LabelConfig),
  change_status: markRaw(ChangeStatusConfig),
  change_priority: markRaw(ChangePriorityConfig),
};

const TYPE_EDITORS = {
  trigger: markRaw(TriggerConfig),
  condition: markRaw(ConditionConfig),
  router: markRaw(RouterConfig),
  wait: markRaw(WaitConfig),
};

const editor = computed(() => {
  if (props.node.type === 'action') {
    return ACTION_EDITORS[props.node.action_name] || markRaw(GenericConfig);
  }
  return TYPE_EDITORS[props.node.type] || markRaw(GenericConfig);
});

const onUpdate = patch => emit('update', patch);
</script>

<template>
  <component :is="editor" :node="node" @update="onUpdate" />
</template>
