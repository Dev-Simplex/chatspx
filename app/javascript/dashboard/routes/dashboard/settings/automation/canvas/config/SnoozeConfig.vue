<script setup>
// Editor da ação `snooze_conversation`: adia (soneca) a conversa por uma DURAÇÃO. Grava em
// action_params = [{ value, unit }] — exatamente o formato que o Flows::SnoozeAction lê para
// calcular snoozed_until. unit ∈ minutes|hours|days|weeks; value é inteiro ≥ 1 (o backend cai
// em snooze INDEFINIDO se value ausente/≤ 0). A conversa reabre sozinha quando o tempo vence
// (Conversations::ReopenSnoozedConversationsJob). Espelha o padrão de WaitConfig.vue.
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

const DEFAULTS = { value: 1, unit: 'hours' };

const config = computed(() => {
  const params = props.node.action_params;
  const first = Array.isArray(params) && params[0] ? params[0] : {};
  return { ...DEFAULTS, ...first };
});

const patch = partial => {
  emit('update', { action_params: [{ ...config.value, ...partial }] });
};

const unitOptions = computed(() => [
  { id: 'minutes', name: t('AUTOMATION.CANVAS.CONFIG.SNOOZE.UNIT_MINUTES') },
  { id: 'hours', name: t('AUTOMATION.CANVAS.CONFIG.SNOOZE.UNIT_HOURS') },
  { id: 'days', name: t('AUTOMATION.CANVAS.CONFIG.SNOOZE.UNIT_DAYS') },
  { id: 'weeks', name: t('AUTOMATION.CANVAS.CONFIG.SNOOZE.UNIT_WEEKS') },
]);

const unitModel = computed({
  get() {
    return (
      unitOptions.value.find(opt => opt.id === config.value.unit) ||
      unitOptions.value[1]
    );
  },
  set(value) {
    patch({ unit: value?.id || 'hours' });
  },
});

const valueModel = computed({
  get() {
    return config.value.value;
  },
  set(value) {
    const parsed = Number.parseInt(value, 10);
    patch({ value: Number.isNaN(parsed) || parsed < 1 ? 1 : parsed });
  },
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.SNOOZE.VALUE_LABEL')">
      <Input
        v-model="valueModel"
        type="number"
        size="sm"
        min="1"
        :placeholder="t('AUTOMATION.CANVAS.CONFIG.SNOOZE.VALUE_PLACEHOLDER')"
      />
    </ConfigField>
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.SNOOZE.UNIT_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.SNOOZE.HINT')"
    >
      <SingleSelect
        v-model="unitModel"
        disable-search
        disable-deselect
        :options="unitOptions"
      />
    </ConfigField>
  </div>
</template>
