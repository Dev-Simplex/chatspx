<script setup>
// Editor dos nós `condition` / `router`. Reusa integralmente o ConditionRow das automações
// e o motor de filterTypes (atributos + operadores + opções). Persiste em `node.conditions`
// na FORMA GERADA (a que o Flows::RunnerService entrega ao ConditionsFilterService).
//
// Contexto de atributos: na F1 usamos o conjunto de `conversation_updated` — o superset de
// atributos de conversa (status, agente, time, prioridade, etiquetas, inbox, idioma...). O
// ConditionsFilterService avalia qualquer um deles independentemente do gatilho.
// TODO(F2): derivar o conjunto do evento do gatilho e ramos rotulados do router.
import {
  ref,
  computed,
  h,
  nextTick,
  onMounted,
  useTemplateRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useOperators } from 'dashboard/components-next/filter/operators';
import { useAutomation } from 'dashboard/composables/useAutomation';
import {
  getAttributes,
  getDefaultConditions,
} from 'dashboard/helper/automationHelper';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ConfigField from './ConfigField.vue';
import {
  INPUT_TYPE_MAP,
  toGeneratedConditions,
  toRichConditions,
} from './conditionHelpers';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const EVENT_CONTEXT = 'conversation_updated';

const { t } = useI18n();
const { operators } = useOperators();
const {
  automationTypes,
  getConditionDropdownValues,
  manifestCustomAttributes,
} = useAutomation();

const conditionsRef = useTemplateRef('conditionsRef');
const conditions = ref([]);
// Trava a emissão durante a (re)hidratação a partir do nó, evitando eco de update.
let isHydrating = false;

const getTranslatedAttributes = () =>
  getAttributes(automationTypes, EVENT_CONTEXT).map(attribute => {
    const skipTranslation =
      attribute.customAttributeType ||
      ['contact_custom_attribute', 'conversation_custom_attribute'].includes(
        attribute.key
      );
    return {
      ...attribute,
      name: skipTranslation
        ? attribute.name
        : t(`AUTOMATION.ATTRIBUTES.${attribute.name}`),
    };
  });

const filterTypes = computed(() =>
  getTranslatedAttributes().map(attr => {
    if (attr.disabled) {
      return { value: attr.key, label: attr.name, disabled: true };
    }
    const mappedInputType = INPUT_TYPE_MAP[attr.inputType] || 'plainText';
    const options = getConditionDropdownValues(attr.key) || [];
    const filterOperators = (attr.filterOperators || []).map(op => {
      const enriched = operators.value[op.value];
      if (enriched) return enriched;
      return {
        value: op.value,
        label: t(`FILTER.OPERATOR_LABELS.${op.value}`),
        hasInput: true,
        inputOverride: null,
        icon: h('span', { class: 'i-lucide-equal !text-n-blue-11' }),
      };
    });
    return {
      attributeKey: attr.key,
      value: attr.key,
      attributeName: attr.name,
      label: attr.name,
      inputType: mappedInputType,
      options,
      filterOperators,
      dataType: 'text',
      attributeModel: attr.customAttributeType || 'standard',
    };
  })
);

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
