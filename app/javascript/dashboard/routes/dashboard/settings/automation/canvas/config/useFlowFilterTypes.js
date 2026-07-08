// Monta o conjunto de `filterTypes` (atributos + operadores + opções) que o ConditionRow das
// automações consome — compartilhado pelos editores de ramificação do canvas Flow
// (ConditionConfig e RouterConfig). Reuso integral do motor de filtro das automações; nada de
// formato novo. Contexto: `conversation_updated` (superset de atributos de conversa), que o
// ConditionsFilterService avalia independentemente do gatilho.
// TODO(F2): derivar o conjunto do evento do gatilho.
import { computed, h } from 'vue';
import { useI18n } from 'vue-i18n';
import { useOperators } from 'dashboard/components-next/filter/operators';
import { useAutomation } from 'dashboard/composables/useAutomation';
import { getAttributes } from 'dashboard/helper/automationHelper';
import { INPUT_TYPE_MAP } from './conditionHelpers';

export const EVENT_CONTEXT = 'conversation_updated';

export function useFlowFilterTypes() {
  const { t } = useI18n();
  const { operators } = useOperators();
  const {
    automationTypes,
    getConditionDropdownValues,
    manifestCustomAttributes,
  } = useAutomation();

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

  return { filterTypes, manifestCustomAttributes };
}
