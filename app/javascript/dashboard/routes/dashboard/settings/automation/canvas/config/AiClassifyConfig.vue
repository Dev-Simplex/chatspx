<script setup>
// Editor do nó de IA `ai_classify`. Pede ao Captain para classificar a conversa em UMA de N
// categorias e grava a categoria escolhida num atributo (custom_attributes por padrão) — que
// um `router`/`condition` posterior lê. action_params =
//   [{ assistant_id, prompt, categories: [...], target, store, key }].
// Reusa a lista de assistentes Captain (captainAssistants/getRecords, carregada no
// FlowCanvasView) — mesma store do nó `assign_ai_agent`.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
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

// Merge-patch da forma canônica (mesmo padrão do SetAttributeConfig): cada edição reconstrói o
// objeto inteiro com os defaults e emite. `store` fica em 'custom' — o backend cai nesse default.
const patch = partial => {
  const next = {
    assistant_id: null,
    prompt: '',
    categories: [],
    target: 'conversation',
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

const categories = computed(() =>
  Array.isArray(config.value.categories) ? config.value.categories : []
);

const updateCategory = (index, value) => {
  const next = [...categories.value];
  next[index] = value;
  patch({ categories: next });
};

const addCategory = () => patch({ categories: [...categories.value, ''] });

const removeCategory = index =>
  patch({ categories: categories.value.filter((_, i) => i !== index) });

const targetOptions = computed(() => [
  {
    id: 'conversation',
    name: t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.TARGET_CONVERSATION'),
  },
  {
    id: 'contact',
    name: t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.TARGET_CONTACT'),
  },
]);

const targetModel = computed({
  get() {
    const id = config.value.target || 'conversation';
    return (
      targetOptions.value.find(opt => opt.id === id) || targetOptions.value[0]
    );
  },
  set(value) {
    patch({ target: value?.id || 'conversation' });
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
  <div class="flex flex-col gap-4" data-testid="config-ai-classify">
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.ASSISTANT_LABEL')"
    >
      <SingleSelect
        v-model="assistantModel"
        :options="assistantOptions"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.ASSISTANT_PLACEHOLDER')
        "
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.PROMPT_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.PROMPT_HINT')"
    >
      <textarea
        v-model="promptModel"
        rows="3"
        class="w-full px-3 py-2 text-sm rounded-lg resize-y outline outline-1 text-n-slate-12 bg-n-alpha-1 outline-n-weak dark:outline-n-strong focus:outline-n-brand"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.PROMPT_PLACEHOLDER')
        "
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.CATEGORIES_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.CATEGORIES_HINT')"
    >
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="(category, ci) in categories"
          :key="ci"
          class="flex items-center gap-1.5"
        >
          <Input
            :model-value="category"
            size="sm"
            class="flex-1"
            :placeholder="
              t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.CATEGORY_PLACEHOLDER')
            "
            @update:model-value="updateCategory(ci, $event)"
          />
          <NextButton
            icon="i-lucide-trash"
            ghost
            ruby
            xs
            :aria-label="
              t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.CATEGORY_REMOVE')
            "
            @click="removeCategory(ci)"
          />
        </li>
        <li class="list-none">
          <NextButton
            icon="i-lucide-plus"
            blue
            faded
            sm
            :label="t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.CATEGORY_ADD')"
            @click="addCategory"
          />
        </li>
      </ul>
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.TARGET_LABEL')"
    >
      <SingleSelect
        v-model="targetModel"
        disable-search
        disable-deselect
        :options="targetOptions"
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.KEY_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.KEY_HINT')"
    >
      <Input
        v-model="attributeKey"
        size="sm"
        :placeholder="t('AUTOMATION.CANVAS.CONFIG.AI_CLASSIFY.KEY_PLACEHOLDER')"
      />
    </ConfigField>
  </div>
</template>
