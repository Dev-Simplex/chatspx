<script setup>
// Editor do nó `wait` (Fase 2): pausa o fluxo por um tempo antes de seguir. Grava em
// node.wait = { value, unit, business_hours } — exatamente o formato que o
// Flows::RunnerService lê para calcular wait_until. unit ∈ minutes|hours|days; value é
// inteiro ≥ 1 (o backend cai em 1 minuto se ausente/inválido). Com business_hours: true o
// instante é empurrado para a próxima abertura comercial da inbox (Flows::BusinessHours).
// Espelha o padrão de SetAttributeConfig.vue.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const DEFAULTS = { value: 5, unit: 'minutes', business_hours: false };

const config = computed(() => ({ ...DEFAULTS, ...(props.node.wait || {}) }));

const patch = partial => {
  emit('update', { wait: { ...config.value, ...partial } });
};

const unitOptions = computed(() => [
  { id: 'minutes', name: t('AUTOMATION.CANVAS.CONFIG.WAIT.UNIT_MINUTES') },
  { id: 'hours', name: t('AUTOMATION.CANVAS.CONFIG.WAIT.UNIT_HOURS') },
  { id: 'days', name: t('AUTOMATION.CANVAS.CONFIG.WAIT.UNIT_DAYS') },
]);

const unitModel = computed({
  get() {
    return (
      unitOptions.value.find(opt => opt.id === config.value.unit) ||
      unitOptions.value[0]
    );
  },
  set(value) {
    patch({ unit: value?.id || 'minutes' });
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

const businessHoursModel = computed({
  get() {
    return Boolean(config.value.business_hours);
  },
  set(value) {
    patch({ business_hours: Boolean(value) });
  },
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.WAIT.VALUE_LABEL')">
      <Input
        v-model="valueModel"
        type="number"
        size="sm"
        min="1"
        :placeholder="t('AUTOMATION.CANVAS.CONFIG.WAIT.VALUE_PLACEHOLDER')"
      />
    </ConfigField>
    <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.WAIT.UNIT_LABEL')">
      <SingleSelect
        v-model="unitModel"
        disable-search
        disable-deselect
        :options="unitOptions"
      />
    </ConfigField>
    <div class="flex flex-col gap-1.5">
      <label
        class="flex items-center justify-between gap-3 cursor-pointer"
        data-testid="wait-business-hours"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('AUTOMATION.CANVAS.CONFIG.WAIT.BUSINESS_HOURS_LABEL') }}
        </span>
        <Switch v-model="businessHoursModel" />
      </label>
      <span class="text-xs leading-snug text-n-slate-10">
        {{ t('AUTOMATION.CANVAS.CONFIG.WAIT.BUSINESS_HOURS_HINT') }}
      </span>
    </div>
  </div>
</template>
