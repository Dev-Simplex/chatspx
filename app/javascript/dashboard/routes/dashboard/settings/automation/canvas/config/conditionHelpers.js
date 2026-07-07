// Conversão entre as DUAS formas das condições de um nó `condition`/`router`:
//
//  • forma "rica" (edição)  — a que o ConditionRow manipula: `values` é objeto {id,name}
//    para search_select, array de {id,name} para multi_select, string para texto.
//  • forma "gerada" (backend) — a que o Flows::RunnerService entrega ao
//    AutomationRules::ConditionsFilterService (via Flows::RuleAdapter): `values` é sempre
//    array de ids/strings. É EXATAMENTE o output do `filterQueryGenerator` das automações.
//
// Persistimos SEMPRE a forma gerada em `node.conditions`; ao abrir um nó salvo reidratamos
// para a forma rica para o editor. Reuso total do motor de condição — sem inventar formato.

import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';

// Espelha o mapa do AutomationRuleForm.vue (inputType do config → inputType do ConditionRow).
export const INPUT_TYPE_MAP = {
  multi_select: 'multiSelect',
  search_select: 'searchSelect',
  plain_text: 'plainText',
  comma_separated_plain_text: 'plainText',
  date: 'date',
};

// Rica → gerada. Delega ao mesmo gerador das automações (deep-clone + last query_operator
// vira undefined), garantindo paridade byte-a-byte com o que o backend já sabe avaliar.
export const toGeneratedConditions = richConditions => {
  if (!Array.isArray(richConditions) || !richConditions.length) return [];
  return filterQueryGenerator(richConditions).payload;
};

const findFilterType = (filterTypes, key) =>
  filterTypes.find(ft => ft.attributeKey === key);

// Reconstrói o `values` rico a partir do array salvo, casando ids com as opções do filtro.
const richValuesFor = (filterType, rawValues, attributeKey) => {
  const values = Array.isArray(rawValues) ? rawValues : [rawValues];
  const options = filterType?.options || [];
  const optionFor = id =>
    options.find(opt => String(opt.id) === String(id)) || { id, name: id };

  switch (filterType?.inputType) {
    case 'multiSelect':
      return values.map(optionFor);
    case 'searchSelect':
      return values.length ? optionFor(values[0]) : {};
    default:
      // `content` foi serializado com split(',') — recompõe juntando; demais são escalares.
      if (attributeKey === 'content') return values.join(',');
      return values.length ? values[0] : '';
  }
};

// Gerada → rica. Best-effort: se um filterType sumiu (ex.: atributo custom removido),
// mantém o valor cru para não perder dados; ao editar, re-persiste no formato correto.
export const toRichConditions = (generatedConditions, filterTypes) => {
  if (!Array.isArray(generatedConditions)) return [];
  return generatedConditions.map((condition, index, all) => {
    const filterType = findFilterType(filterTypes, condition.attribute_key);
    return {
      attribute_key: condition.attribute_key,
      filter_operator: condition.filter_operator,
      values: richValuesFor(
        filterType,
        condition.values,
        condition.attribute_key
      ),
      query_operator:
        index === all.length - 1 ? null : condition.query_operator || 'and',
      custom_attribute_type: condition.custom_attribute_type || '',
    };
  });
};
