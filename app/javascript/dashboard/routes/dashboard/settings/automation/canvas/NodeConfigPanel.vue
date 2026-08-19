<script setup>
// Dispatcher dos editores de nó: escolhe o SFC de configuração conforme o type/action_name
// do nó e repassa o patch de `update` para cima. Cada editor recebe `:node` e emite
// `update` com o pedaço da definition a alterar (action_params, conditions ou event_name).
import { computed, markRaw } from 'vue';
import { interactiveOptionsForWait } from './waitForReply';
import TriggerConfig from './config/TriggerConfig.vue';
import ConditionConfig from './config/ConditionConfig.vue';
import RouterConfig from './config/RouterConfig.vue';
import MessageConfig from './config/MessageConfig.vue';
import SendTemplateConfig from './config/SendTemplateConfig.vue';
import SendInteractiveConfig from './config/SendInteractiveConfig.vue';
import CtaUrlConfig from './config/CtaUrlConfig.vue';
import LocationRequestConfig from './config/LocationRequestConfig.vue';
import WhatsappFlowConfig from './config/WhatsappFlowConfig.vue';
import SetAttributeConfig from './config/SetAttributeConfig.vue';
import MoveFunnelStageConfig from './config/MoveFunnelStageConfig.vue';
import CallMacroConfig from './config/CallMacroConfig.vue';
import HttpRequestConfig from './config/HttpRequestConfig.vue';
import AssignAgentConfig from './config/AssignAgentConfig.vue';
import AssignTeamConfig from './config/AssignTeamConfig.vue';
import AddParticipantConfig from './config/AddParticipantConfig.vue';
import EnrollSequenceConfig from './config/EnrollSequenceConfig.vue';
import AssignAiAgentConfig from './config/AssignAiAgentConfig.vue';
import AiClassifyConfig from './config/AiClassifyConfig.vue';
import AiGenerateConfig from './config/AiGenerateConfig.vue';
import LabelConfig from './config/LabelConfig.vue';
import ChangeStatusConfig from './config/ChangeStatusConfig.vue';
import ChangePriorityConfig from './config/ChangePriorityConfig.vue';
import WaitConfig from './config/WaitConfig.vue';
import WaitForReplyConfig from './config/WaitForReplyConfig.vue';
import SnoozeConfig from './config/SnoozeConfig.vue';
import SendEmailToTeamConfig from './config/SendEmailToTeamConfig.vue';
import SendEmailTranscriptConfig from './config/SendEmailTranscriptConfig.vue';
import SendWebhookEventConfig from './config/SendWebhookEventConfig.vue';
import SendAttachmentConfig from './config/SendAttachmentConfig.vue';
import AddSlaConfig from './config/AddSlaConfig.vue';
import GenericConfig from './config/GenericConfig.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
  // Grafo inteiro: alguns editores precisam olhar os VIZINHOS do nó, não só ele. Hoje só o
  // `wait_for_reply` usa (para listar as opções do `send_interactive` que desemboca nele).
  definition: {
    type: Object,
    default: () => ({ nodes: [], edges: [] }),
  },
});

const emit = defineEmits(['update']);

const ACTION_EDITORS = {
  send_message: markRaw(MessageConfig),
  add_private_note: markRaw(MessageConfig),
  send_template: markRaw(SendTemplateConfig),
  send_interactive: markRaw(SendInteractiveConfig),
  send_cta_url: markRaw(CtaUrlConfig),
  send_location_request: markRaw(LocationRequestConfig),
  send_whatsapp_flow: markRaw(WhatsappFlowConfig),
  set_attribute: markRaw(SetAttributeConfig),
  move_funnel_stage: markRaw(MoveFunnelStageConfig),
  call_macro: markRaw(CallMacroConfig),
  http_request: markRaw(HttpRequestConfig),
  assign_agent: markRaw(AssignAgentConfig),
  assign_team: markRaw(AssignTeamConfig),
  add_participant: markRaw(AddParticipantConfig),
  enroll_in_sequence: markRaw(EnrollSequenceConfig),
  assign_ai_agent: markRaw(AssignAiAgentConfig),
  ai_classify: markRaw(AiClassifyConfig),
  ai_generate: markRaw(AiGenerateConfig),
  add_label: markRaw(LabelConfig),
  remove_label: markRaw(LabelConfig),
  change_status: markRaw(ChangeStatusConfig),
  change_priority: markRaw(ChangePriorityConfig),
  snooze_conversation: markRaw(SnoozeConfig),
  send_email_to_team: markRaw(SendEmailToTeamConfig),
  send_email_transcript: markRaw(SendEmailTranscriptConfig),
  send_webhook_event: markRaw(SendWebhookEventConfig),
  send_attachment: markRaw(SendAttachmentConfig),
  add_sla: markRaw(AddSlaConfig),
};

const TYPE_EDITORS = {
  trigger: markRaw(TriggerConfig),
  condition: markRaw(ConditionConfig),
  router: markRaw(RouterConfig),
  wait: markRaw(WaitConfig),
  wait_for_reply: markRaw(WaitForReplyConfig),
};

// Props EXTRA por editor. Passamos só ao editor que declara a prop — um v-bind indiscriminado
// viraria atributo solto no DOM (fallthrough) nos demais.
const editorProps = computed(() => {
  if (props.node.type !== 'wait_for_reply') return {};
  return {
    sourceOptions: interactiveOptionsForWait(props.definition, props.node.id),
  };
});

const editor = computed(() => {
  if (props.node.type === 'action') {
    return ACTION_EDITORS[props.node.action_name] || markRaw(GenericConfig);
  }
  return TYPE_EDITORS[props.node.type] || markRaw(GenericConfig);
});

const onUpdate = patch => emit('update', patch);
</script>

<template>
  <component
    :is="editor"
    :node="node"
    v-bind="editorProps"
    @update="onUpdate"
  />
</template>
