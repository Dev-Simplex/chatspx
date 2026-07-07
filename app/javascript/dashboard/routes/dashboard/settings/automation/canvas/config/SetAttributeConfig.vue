<script setup>
// Editor de `set_attribute`. action_params = [{ target, store, key, value }].
//   • target: 'conversation' (default) | 'contact'   → onde gravar
//   • key:    nome do atributo
//   • value:  valor (aceita Liquid {{contact.name}})
// `store` fica em 'custom' (custom_attributes) — o backend cai nesse default quando ausente.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
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

const config = computed(() => {
  const params = props.node.action_params;
  return Array.isArray(params) && params[0] ? params[0] : {};
});

const patch = partial => {
  const next = {
    target: 'conversation',
    store: 'custom',
    key: '',
    value: '',
    ...config.value,
    ...partial,
  };
  emit('update', { action_params: [next] });
};

const targetOptions = computed(() => [
  {
    id: 'conversation',
    name: t('AUTOMATION.CANVAS.CONFIG.SET_ATTRIBUTE.TARGET_CONVERSATION'),
  },
  {
    id: 'contact',
    name: t('AUTOMATION.CANVAS.CONFIG.SET_ATTRIBUTE.TARGET_CONTACT'),
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

const attributeValue = computed({
  get() {
    return config.value.value || '';
  },
  set(value) {
    patch({ value });
  },
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.SET_ATTRIBUTE.TARGET_LABEL')"
    >
      <SingleSelect
        v-model="targetModel"
        disable-search
        disable-deselect
        :options="targetOptions"
      />
    </ConfigField>
    <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.SET_ATTRIBUTE.KEY_LABEL')">
      <Input
        v-model="attributeKey"
        size="sm"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.SET_ATTRIBUTE.KEY_PLACEHOLDER')
        "
      />
    </ConfigField>
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.SET_ATTRIBUTE.VALUE_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.SET_ATTRIBUTE.VALUE_HINT')"
    >
      <Input
        v-model="attributeValue"
        size="sm"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.SET_ATTRIBUTE.VALUE_PLACEHOLDER')
        "
      />
    </ConfigField>
  </div>
</template>
