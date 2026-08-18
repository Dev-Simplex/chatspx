/**
 * Bloco 3.14 — as regras do construtor de pré-chat, separadas dos componentes.
 *
 * Ficam aqui e não dentro dos `.vue` porque **são elas que os aceites cobram**
 * (teto de 8, condicional só de etapa anterior, migração sem perda) e regra
 * escondida em componente só é verificável montando o componente inteiro.
 */
import { MASK_NAMES, VALIDATOR_NAMES } from 'shared/helpers/brMasks';

/**
 * Teto do §B.4.4: 8 campos no total, somando todas as etapas.
 *
 * Conta campo **HABILITADO**, não entrada do array. O array carrega todo
 * atributo personalizado da conta com `enabled: false`
 * (`helper/preChat.js#getCustomFields`), então uma conta com 12 atributos tem
 * 12 entradas e nenhum formulário longo. Contar entradas travaria a tela de
 * quem nunca configurou nada — e foi por isso que o schema do 3.12 também não
 * ganhou `maxItems`.
 */
export const MAX_ENABLED_FIELDS = 8;

/** Uma etapa por campo é o limite útil; mais etapas que campos é engano. */
export const MAX_STEPS = 8;

export const MODES = ['simple', 'builder', 'flow'];

export const CONDITION_OPERATORS = ['is', 'is_not', 'contains', 'filled'];

/** Operador que dispensa valor — "preenchido" não compara com nada. */
export const OPERATORS_WITHOUT_VALUE = ['filled'];

export { MASK_NAMES, VALIDATOR_NAMES };

/** Campo sem `step` é da etapa 1: é assim que todo formulário de hoje é lido. */
export const stepOf = field => Number(field?.step) || 1;

export const enabledFields = (fields = []) => fields.filter(f => f?.enabled);

export const enabledCount = (fields = []) => enabledFields(fields).length;

export const isAtFieldLimit = (fields = []) =>
  enabledCount(fields) >= MAX_ENABLED_FIELDS;

/** Quantas etapas o formulário tem hoje, olhando só campo habilitado. */
export const stepCount = (fields = []) => {
  const steps = enabledFields(fields).map(stepOf);
  return steps.length ? Math.max(...steps) : 1;
};

export const canAddStep = (fields = []) => stepCount(fields) < MAX_STEPS;

/**
 * Os campos habilitados de uma etapa, na ordem de `position` e, em empate, na
 * ordem em que estão no array — que é a ordem que a tela antiga já usava.
 *
 * Campo SEM `position` vai para o fim, e não para a frente: a tela antiga não
 * grava `position`, então um formulário legado que ganha um campo ordenado
 * manteria a ordem antiga e receberia o novo no fim — que é o que quem
 * configurou espera. Tratar ausência como zero embaralharia o formulário
 * inteiro na primeira reordenação.
 */
const positionOf = field =>
  Number.isFinite(Number(field?.position))
    ? Number(field.position)
    : Number.MAX_SAFE_INTEGER;

export const fieldsOfStep = (fields, step) =>
  enabledFields(fields)
    .map((field, index) => ({ field, index }))
    .filter(({ field }) => stepOf(field) === step)
    .sort((a, b) => {
      const byPosition = positionOf(a.field) - positionOf(b.field);
      return byPosition !== 0 ? byPosition : a.index - b.index;
    })
    .map(({ field }) => field);

/** `[{ step: 1, fields: [...] }, …]`, sempre com pelo menos a etapa 1. */
export const groupByStep = (fields = []) =>
  Array.from({ length: stepCount(fields) }, (_, index) => ({
    step: index + 1,
    fields: fieldsOfStep(fields, index + 1),
  }));

/**
 * A condicional só pode olhar campo de etapa **anterior** (§B.4.4): um campo
 * não pode depender de resposta que o visitante ainda não deu — a etapa 2 só
 * carrega depois da 1.
 */
export const conditionSources = (fields, step) =>
  enabledFields(fields).filter(field => stepOf(field) < step);

export const isConditionComplete = condition => {
  if (!condition?.field || !condition?.operator) return false;
  if (OPERATORS_WITHOUT_VALUE.includes(condition.operator)) return true;
  return Boolean(String(condition.value ?? '').trim());
};

/**
 * A condicional aponta para um campo que sumiu (foi desabilitado, ou mudou de
 * etapa e deixou de ser anterior)? Isso é uma promessa quebrada dentro do
 * formulário do visitante, então a tela precisa saber nomear o problema.
 */
export const danglingConditions = (fields = []) =>
  enabledFields(fields)
    .filter(field => field.show_if?.field)
    .filter(field => {
      const sources = conditionSources(fields, stepOf(field)).map(f => f.name);
      return !sources.includes(field.show_if.field);
    })
    .map(field => ({ name: field.name, target: field.show_if.field }));

const hasBuilderFeature = field =>
  stepOf(field) > 1 ||
  Boolean(field?.show_if) ||
  Boolean(field?.mask) ||
  Boolean(field?.validator) ||
  Boolean(field?.help_text);

/**
 * O modo LIDO DO CONTEÚDO — o retrato do que está gravado.
 *
 * Só vale como fallback: derivar infere **intenção** a partir de **sintoma**.
 * Um formulário montado no construtor que por acaso ficou com uma etapa e
 * nenhum recurso avançado voltaria sozinho para "Simples", e o administrador
 * veria a tela trocar de modo sem ter pedido.
 */
export const deriveMode = (options = {}) =>
  (options.pre_chat_fields ?? []).some(hasBuilderFeature)
    ? 'builder'
    : 'simple';

/**
 * O modo de verdade: o que está gravado em `pre_chat_form_options.mode`
 * (bloco 3.12/3.14) e, na ausência dele, o derivado.
 *
 * A frota inteira está sem `mode` hoje — a chave nasceu neste bloco e **não há
 * backfill**. Por isso a ausência não é erro: é o caso comum, e ela é lida como
 * o retrato do conteúdo. Valor fora do enum cai no mesmo caminho da ausência,
 * em vez de deixar a tela num modo que o servidor recusa gravar.
 */
export const resolveMode = (options = {}) =>
  MODES.includes(options?.mode) ? options.mode : deriveMode(options);

/**
 * Simples → Construtor. Não muda campo nenhum de lugar: só torna explícito o
 * que já era implícito (etapa 1, posição pela ordem do array). Sem isso, a
 * primeira reordenação no construtor embaralharia o formulário.
 */
export const toBuilder = (fields = []) => {
  let position = 0;
  return fields.map(field => {
    if (!field?.enabled) return { ...field };
    const next = { ...field, step: stepOf(field), position };
    position += 1;
    return next;
  });
};

/**
 * Construtor → Simples. **Não apaga nada** (§B.4.1): traz todos os campos para
 * a etapa 1 e devolve, junto, o que a volta custa — as etapas que somem e as
 * condicionais que deixam de valer. Quem chama mostra isso ANTES de aplicar.
 */
export const toSimple = (fields = []) => {
  const ignoredSteps = [
    ...new Set(
      enabledFields(fields)
        .map(stepOf)
        .filter(step => step > 1)
    ),
  ].sort((a, b) => a - b);

  const droppedConditions = enabledFields(fields)
    .filter(field => field.show_if)
    .map(field => field.name);

  const next = fields.map(field => {
    if (!field?.enabled) return { ...field };
    const { show_if: _ignored, ...rest } = field;
    return { ...rest, step: 1 };
  });

  return { fields: next, ignoredSteps, droppedConditions };
};

/** Reordena dentro de uma etapa reescrevendo `position` — nunca o array todo. */
export const applyOrder = (fields, step, orderedNames = []) =>
  fields.map(field => {
    if (!field?.enabled || stepOf(field) !== step) return { ...field };
    const position = orderedNames.indexOf(field.name);
    return position === -1 ? { ...field } : { ...field, position };
  });

/** Liga um campo, respeitando o teto. Devolve a lista intacta quando cheio. */
export const enableField = (fields, name, step = 1) => {
  if (isAtFieldLimit(fields)) return fields;
  return fields.map(field =>
    field?.name === name
      ? {
          ...field,
          enabled: true,
          step,
          position: fieldsOfStep(fields, step).length,
        }
      : { ...field }
  );
};

/**
 * Desliga um campo e limpa a condicional de quem apontava para ele — deixar a
 * referência órfã esconderia um campo do visitante para sempre, sem que a tela
 * mostre por quê.
 */
export const disableField = (fields, name) =>
  fields.map(field => {
    if (field?.name === name) return { ...field, enabled: false };
    if (field?.show_if?.field !== name) return { ...field };
    const { show_if: _dropped, ...rest } = field;
    return { ...rest };
  });

/**
 * Aplica uma mudança num campo.
 *
 * Chave com valor `null` é REMOVIDA, não gravada como `null`. A razão é o
 * servidor: no JSON Schema do 3.12, `show_if` é `type: object` com `field` e
 * `operator` obrigatórios — `show_if: null` **não** é objeto e volta 422. É
 * exatamente o que aconteceria ao clicar em "Sempre mostrar", que é a operação
 * mais banal do editor de condicional.
 */
export const updateField = (fields, name, patch = {}) =>
  fields.map(field => {
    if (field?.name !== name) return { ...field };

    const next = { ...field, ...patch };
    Object.entries(patch).forEach(([key, value]) => {
      if (value === null || value === undefined) delete next[key];
    });
    return next;
  });
