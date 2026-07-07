<script setup>
// Editor de `change_status`. action_params = [status]. Status válidos da conversa
// (enum status: open/resolved/pending/snoozed).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
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

const options = computed(() => [
  { id: 'open', name: t('AUTOMATION.CANVAS.CONFIG.CHANGE_STATUS.OPEN') },
  {
    id: 'resolved',
    name: t('AUTOMATION.CANVAS.CONFIG.CHANGE_STATUS.RESOLVED'),
  },
  { id: 'pending', name: t('AUTOMATION.CANVAS.CONFIG.CHANGE_STATUS.PENDING') },
  { id: 'snoozed', name: t('AUTOMATION.CANVAS.CONFIG.CHANGE_STATUS.SNOOZED') },
]);

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
  <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.CHANGE_STATUS.LABEL')">
    <SingleSelect
      v-model="selected"
      disable-search
      :options="options"
      :placeholder="t('AUTOMATION.CANVAS.CONFIG.CHANGE_STATUS.PLACEHOLDER')"
    />
  </ConfigField>
</template>
