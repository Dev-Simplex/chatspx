<script setup>
// Editor de `add_sla` (ENTERPRISE). action_params = [sla_policy_id]. Aplica uma política de SLA à
// conversa via Enterprise::ActionService#add_sla (enterprise/app/services/enterprise/action_service.rb:2)
// — `@account.sla_policies.find_by(id: sla_policy_id.first)`, e só se a conversa ainda não tiver SLA.
// Enterprise pela mesma razão do assign_ai_agent/ai_* (já no catálogo): Enterprise::Flow soma add_sla
// a allowed_action_names. Busca as políticas sob demanda (o canvas não pré-carrega `sla/get`); sem
// enterprise/SLA a lista fica vazia (o dispatch é no-op silencioso) e o backend faz no-op também.
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
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
const store = useStore();
const slaPolicies = useMapGetter('sla/getSLA');

const options = computed(() =>
  slaPolicies.value.map(policy => ({ id: policy.id, name: policy.name }))
);

const selected = computed({
  get() {
    const current = props.node.action_params?.[0];
    if (current === undefined || current === null || current === '')
      return null;
    return (
      options.value.find(opt => String(opt.id) === String(current)) || null
    );
  },
  set(value) {
    emit('update', { action_params: value ? [value.id] : [] });
  },
});

onMounted(() => {
  if (!slaPolicies.value.length) store.dispatch('sla/get');
});
</script>

<template>
  <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.ADD_SLA.LABEL')">
    <SingleSelect
      v-model="selected"
      :options="options"
      :placeholder="t('AUTOMATION.CANVAS.CONFIG.ADD_SLA.PLACEHOLDER')"
    />
    <p v-if="!options.length" class="mt-1 text-xs text-n-slate-10">
      {{ t('AUTOMATION.CANVAS.CONFIG.ADD_SLA.NO_POLICIES') }}
    </p>
  </ConfigField>
</template>
