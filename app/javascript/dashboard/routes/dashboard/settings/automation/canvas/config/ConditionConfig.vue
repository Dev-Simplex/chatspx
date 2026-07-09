<script setup>
// Editor do nó `condition` (2 saídas Sim/Não). Reusa integralmente o ConditionRow das
// automações e o motor de filterTypes (atributos + operadores + opções). Persiste em
// `node.conditions` na FORMA GERADA (a que o Flows::RunnerService entrega ao
// ConditionsFilterService). O nó `router` (multi-rota) tem editor próprio: RouterConfig.vue.
//
// filterTypes (atributos/operadores/opções, contexto `conversation_updated`) vêm do composable
// compartilhado useFlowFilterTypes — o mesmo conjunto que o RouterConfig usa. Reuso integral
// do motor de filtro das automações; nada de formato novo.
import { ref, nextTick, onMounted, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { getDefaultConditions } from 'dashboard/helper/automationHelper';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ConfigField from './ConfigField.vue';
import { toGeneratedConditions, toRichConditions } from './conditionHelpers';
import { useFlowFilterTypes, EVENT_CONTEXT } from './useFlowFilterTypes';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();
const { filterTypes, manifestCustomAttributes } = useFlowFilterTypes();

const conditionsRef = useTemplateRef('conditionsRef');
const conditions = ref([]);
// Trava a emissão durante a (re)hidratação a partir do nó, evitando eco de update.
let isHydrating = false;

const hydrateFromNode = () => {
  isHydrating = true;
  const stored = props.node.conditions;
  conditions.value =
    Array.isArray(stored) && stored.length
      ? toRichConditions(stored, filterTypes.value)
      : getDefaultConditions(EVENT_CONTEXT);
  // Solta a trava só APÓS o watcher da hidratação drenar (ele é assíncrono) — assim abrir
  // um nó não emite update; só edições reais do usuário persistem.
  nextTick(() => {
    isHydrating = false;
  });
};

const appendCondition = () => {
  conditions.value = [
    ...conditions.value,
    ...getDefaultConditions(EVENT_CONTEXT),
  ];
};

const removeCondition = index => {
  conditions.value = conditions.value.filter((_, i) => i !== index);
};

onMounted(() => {
  manifestCustomAttributes();
  hydrateFromNode();
});

// Troca de nó selecionado: re-hidrata a partir do novo nó.
watch(
  () => props.node.id,
  () => hydrateFromNode()
);

// Qualquer edição das condições → persiste a forma gerada no nó.
watch(
  conditions,
  value => {
    if (isHydrating) return;
    emit('update', { conditions: toGeneratedConditions(value) });
  },
  { deep: true }
);
</script>

<template>
  <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.CONDITION.LABEL')">
    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <template v-for="(condition, i) in conditions" :key="i">
        <ConditionRow
          v-if="i === 0"
          ref="conditionsRef"
          v-model:attribute-key="conditions[i].attribute_key"
          v-model:filter-operator="conditions[i].filter_operator"
          v-model:values="conditions[i].values"
          :filter-types="filterTypes"
          :show-query-operator="false"
          @remove="removeCondition(i)"
        />
        <ConditionRow
          v-else
          ref="conditionsRef"
          v-model:attribute-key="conditions[i].attribute_key"
          v-model:filter-operator="conditions[i].filter_operator"
          v-model:query-operator="conditions[i - 1].query_operator"
          v-model:values="conditions[i].values"
          :filter-types="filterTypes"
          show-query-operator
          @remove="removeCondition(i)"
        />
      </template>
      <li class="list-none">
        <NextButton
          icon="i-lucide-plus"
          blue
          faded
          sm
          :label="t('AUTOMATION.CANVAS.CONFIG.CONDITION.ADD')"
          @click="appendCondition"
        />
      </li>
    </ul>
  </ConfigField>
</template>
