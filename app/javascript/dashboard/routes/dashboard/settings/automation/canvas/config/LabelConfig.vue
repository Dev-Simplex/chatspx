<script setup>
// Editor de `add_label` / `remove_label`. action_params = [title, ...] (etiquetas por
// título — é assim que o ActionService#add_labels casa).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();
const labels = useMapGetter('labels/getLabels');

const isRemove = computed(() => props.node.action_name === 'remove_label');

const options = computed(() =>
  labels.value.map(label => ({ id: label.title, name: label.title }))
);

const selected = computed({
  get() {
    const params = props.node.action_params;
    if (!Array.isArray(params)) return [];
    return params.map(title => ({ id: title, name: title }));
  },
  set(value) {
    emit('update', {
      action_params: Array.isArray(value) ? value.map(item => item.id) : [],
    });
  },
});
</script>

<template>
  <ConfigField
    :label="
      isRemove
        ? t('AUTOMATION.CANVAS.CONFIG.LABELS.REMOVE_LABEL')
        : t('AUTOMATION.CANVAS.CONFIG.LABELS.ADD_LABEL')
    "
  >
    <MultiSelect v-model="selected" :options="options" />
  </ConfigField>
</template>
