<script setup>
// Editor do nó de IA `ai_generate`. Pede ao Captain um texto (ex.: rascunho de resposta) e o
// grava numa NOTA interna (padrão) ou num atributo. action_params =
//   [{ assistant_id, prompt, target: 'note' | 'attribute', attribute_target, store, key }].
// Reusa a lista de assistentes Captain (captainAssistants/getRecords) — como o `assign_ai_agent`.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
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

const config = computed(() => {
  const params = props.node.action_params;
  return Array.isArray(params) && params[0] ? params[0] : {};
});

const patch = partial => {
  const next = {
    assistant_id: null,
    prompt: '',
    target: 'note',
    attribute_target: 'conversation',
    store: 'custom',
    key: '',
    ...config.value,
    ...partial,
  };
  emit('update', { action_params: [next] });
};

const assistantOptions = computed(() =>
  aiAgents.value.map(agent => ({ id: agent.id, name: agent.name }))
);

const assistantModel = computed({
  get() {
    const current = config.value.assistant_id;
    if (current === undefined || current === null || current === '')
      return null;
    return (
      assistantOptions.value.find(opt => String(opt.id) === String(current)) ||
      null
    );
  },
  set(value) {
    patch({ assistant_id: value ? value.id : null });
  },
});

const promptModel = computed({
  get() {
    return config.value.prompt || '';
  },
  set(value) {
    patch({ prompt: value });
  },
});

const targetOptions = computed(() => [
  {
    id: 'note',
    name: t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.TARGET_NOTE'),
  },
  {
    id: 'attribute',
    name: t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.TARGET_ATTRIBUTE'),
  },
]);

const targetModel = computed({
  get() {
    const id = config.value.target || 'note';
    return (
      targetOptions.value.find(opt => opt.id === id) || targetOptions.value[0]
    );
  },
  set(value) {
    patch({ target: value?.id || 'note' });
  },
});

const isAttribute = computed(() => config.value.target === 'attribute');

const attributeTargetOptions = computed(() => [
  {
    id: 'conversation',
    name: t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.WHERE_CONVERSATION'),
  },
  {
    id: 'contact',
    name: t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.WHERE_CONTACT'),
  },
]);

const attributeTargetModel = computed({
  get() {
    const id = config.value.attribute_target || 'conversation';
    return (
      attributeTargetOptions.value.find(opt => opt.id === id) ||
      attributeTargetOptions.value[0]
    );
  },
  set(value) {
    patch({ attribute_target: value?.id || 'conversation' });
  },
});

const attributeKey = computed({
  get() {
    return config.value.key || '';
  },
  set(value) {
    patch({ key: value });
  },
});
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="config-ai-generate">
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.ASSISTANT_LABEL')"
    >
      <SingleSelect
        v-model="assistantModel"
        :options="assistantOptions"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.ASSISTANT_PLACEHOLDER')
        "
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.PROMPT_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.PROMPT_HINT')"
    >
      <textarea
        v-model="promptModel"
        rows="4"
        class="w-full px-3 py-2 text-sm rounded-lg resize-y outline outline-1 text-n-slate-12 bg-n-alpha-1 outline-n-weak dark:outline-n-strong focus:outline-n-brand"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.PROMPT_PLACEHOLDER')
        "
        data-testid="config-ai-generate-prompt"
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.TARGET_LABEL')"
    >
      <SingleSelect
        v-model="targetModel"
        disable-search
        disable-deselect
        :options="targetOptions"
      />
    </ConfigField>

    <template v-if="isAttribute">
      <ConfigField
        :label="t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.WHERE_LABEL')"
      >
        <SingleSelect
          v-model="attributeTargetModel"
          disable-search
          disable-deselect
          :options="attributeTargetOptions"
        />
      </ConfigField>
      <ConfigField
        :label="t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.KEY_LABEL')"
        :hint="t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.KEY_HINT')"
      >
        <Input
          v-model="attributeKey"
          size="sm"
          :placeholder="
            t('AUTOMATION.CANVAS.CONFIG.AI_GENERATE.KEY_PLACEHOLDER')
          "
        />
      </ConfigField>
    </template>
  </div>
</template>
