<script setup>
// Editor de `change_priority`. action_params = [priority]. Reusa os valores/labels de
// prioridade das automações (nil/low/medium/high/urgent). O backend trata 'nil' como null.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import { PRIORITY_CONDITION_VALUES } from 'dashboard/constants/automation';
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
  PRIORITY_CONDITION_VALUES.map(item => ({
    id: item.id,
    name: t(`AUTOMATION.PRIORITY_TYPES.${item.i18nKey}`),
  }))
);

const selected = computed({
  get() {
    const current = props.node.action_params?.[0];
    return options.value.find(opt => opt.id === current) || null;
  },
  set(value) {
    emit('update', { action_params: value ? [value.id] : [] });
  },
});
</script>

<template>
  <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.CHANGE_PRIORITY.LABEL')">
    <SingleSelect
      v-model="selected"
      disable-search
      :options="options"
      :placeholder="t('AUTOMATION.CANVAS.CONFIG.CHANGE_PRIORITY.PLACEHOLDER')"
    />
  </ConfigField>
</template>
