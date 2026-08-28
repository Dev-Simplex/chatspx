/**
 * BLOCO 3.15 — as regras de campo do pré-chat, do lado do WIDGET.
 *
 * Este arquivo é a ponta CONSUMIDORA de um contrato que a trilha de pré-chat
 * fechou nos blocos 3.12 e 3.13. O produtor é
 * `app/models/channel/web_widget/pre_chat_form_schema.rb`; o vocabulário abaixo
 * foi conferido contra ele, chave por chave.
 *
 * Ele existe para `PreChat/Form.vue` continuar sendo uma CASCA: a lógica de
 * visibilidade, etapa, máscara e validação mora aqui, pura e testável, e o
 * componente só a chama. Reescrever o formulário era o que o bloco proibia.
 *
 * Máscara e validação NÃO são reimplementadas: delegam a
 * `widget/helpers/brMasks` (que reexporta `shared/helpers/brMasks`), entregue
 * pelo 3.13. Nome que exista de um lado só é campo que a tela oferece e o
 * widget ignora — por isso não há vocabulário paralelo aqui.
 */
import { applyMask, validateFieldValue } from 'widget/helpers/brMasks';

/** Espelha `CONDITION_OPERATORS` do schema Ruby. */
export const CONDITION_OPERATORS = ['is', 'is_not', 'contains', 'filled'];

/** Espelha `MAX_STEP` do schema Ruby. */
export const MAX_STEP = 8;

/** Operadores que precisam de um `value` para significar alguma coisa. */
const OPERATORS_NEEDING_VALUE = ['is', 'is_not', 'contains'];

const normalize = value => String(value ?? '').trim();
const fold = value => normalize(value).toLowerCase();

/**
 * Tipos de campo em que o formulário GUARDA uma coisa e a pessoa LEU outra.
 *
 * `list` é o nome do painel (`custom_attribute_definition.rb:58`); `select` é o
 * mesmo campo depois de o widget mapear o tipo para o FormKit. Os dois entram
 * porque a função é chamada dos dois lados do mapeamento.
 */
const LIST_TYPES = ['list', 'select'];

/**
 * Vocabulário FECHADO de uma caixa de seleção.
 *
 * Ele existe porque o `value` da condicional é um campo de TEXTO LIVRE no painel
 * (`ConditionEditor.vue:112` é um `Input`, sem enum e sem tipo): não há como
 * quem configura escolher "marcado" numa lista, então ele digita. A alternativa
 * — comparar o booleano com a string crua — dá `'true' === 'sim'` falso para
 * toda redação plausível, e o campo condicional nunca aparece.
 */
const AFFIRMATIVE = ['true', '1', 'sim', 'yes', 'marcado', 'checked'];
const NEGATIVE = ['false', '0', 'nao', 'não', 'no', 'desmarcado', 'unchecked'];

/** `null` quando a palavra não pertence ao vocabulário — não é `false`. */
const parseBoolean = value => {
  const word = fold(value);
  if (AFFIRMATIVE.includes(word)) return true;
  if (NEGATIVE.includes(word)) return false;
  return null;
};

/**
 * O valor do campo COMO A PESSOA O LEU — e não como o formulário o guardou.
 *
 * É a correção central deste arquivo. O `select` do pré-chat é montado com as
 * opções indexadas por POSIÇÃO (`getOptions` em `PreChat/Form.vue`), então
 * `formValues.tipo` vale `'0'`, nunca `'Empresa'`. Quem configura a condicional
 * no painel digita o RÓTULO, porque é o que está escrito na tela dele. Comparar
 * os dois sem resolver não casa nunca, e o campo condicional simplesmente não
 * aparece — sem erro, sem log, sem teste vermelho.
 *
 * A caixa de seleção tem o mesmo problema por outro caminho: o FormKit guarda
 * um BOOLEANO, e `String(false)` tem cinco letras, o que fazia `filled` dar
 * verdadeiro para caixa DESMARCADA.
 *
 * Posição fora da lista devolve o valor cru, e é a mesma assimetria de dano do
 * resto do arquivo: lista encurtada no painel depois de a pessoa responder não
 * pode fazer o campo sumir.
 */
export const resolveFieldValue = (field, raw) => {
  const type = field?.type;
  if (type === 'checkbox') return raw === true || fold(raw) === 'true';
  if (!LIST_TYPES.includes(type)) return raw;

  const options = Array.isArray(field.values) ? field.values : [];
  // `/^\d+$/` e não `Number(raw)`: `Number('')` é 0, e a lista NÃO respondida
  // viraria a primeira opção — o pior erro possível aqui, porque é silencioso e
  // sempre a favor de mostrar o campo errado.
  if (!/^\d+$/.test(normalize(raw))) return raw;
  const index = Number(normalize(raw));
  return index < options.length ? options[index] : raw;
};

/** A condição sobre uma caixa de seleção, que é booleana e não textual. */
const evaluateBooleanCondition = (condition, checked) => {
  if (condition.operator === 'filled') return checked === true;

  const target = parseBoolean(condition.value);
  // "Empresa" numa caixa de seleção é engano de configuração: a condição não
  // teria como ser satisfeita nunca. Falha ABERTA, como o resto do arquivo.
  if (target === null) return true;
  if (condition.operator === 'is_not') return checked !== target;
  // `is` e `contains` colapsam: não existe substring dentro de um booleano.
  return checked === target;
};

/**
 * A condição está bem formada?
 *
 * O schema já recusa o que é malformado NA ESCRITA (`show_if` é `type: object`
 * com `required: [field, operator]`). Mas o widget lê o que chegou, não o que
 * deveria ter chegado: payload antigo, conta migrada à mão ou um bug de outra
 * ponta produzem forma inválida sem pedir licença.
 */
export const isConditionWellFormed = condition => {
  if (!condition || typeof condition !== 'object' || Array.isArray(condition)) {
    return false;
  }
  if (!normalize(condition.field)) return false;
  if (!CONDITION_OPERATORS.includes(condition.operator)) return false;
  if (
    OPERATORS_NEEDING_VALUE.includes(condition.operator) &&
    !normalize(condition.value)
  ) {
    return false;
  }
  return true;
};

/**
 * Avalia a condição contra os valores já preenchidos.
 *
 * O terceiro parâmetro são os CAMPOS, não os nomes deles: sem o `type` e sem o
 * `values` do gatilho não há como resolver o que a pessoa realmente respondeu
 * (ver `resolveFieldValue`), e comparar a chave do FormKit com o rótulo que o
 * painel gravou é justamente o defeito que este bloco fecha.
 *
 * @param {object} condition o `show_if` do campo
 * @param {object} values    valores atuais do formulário, por nome de campo
 * @param {object[]} fields  os campos do formulário, com `name`, `type`, `values`
 * @returns {boolean} true = mostrar o campo
 */
export const evaluateCondition = (condition, values = {}, fields = []) => {
  // FALHA ABERTA, e é a decisão central deste arquivo.
  //
  // Condição ausente, nula, vazia, com operador desconhecido, sem `value` onde
  // ele é necessário, ou apontando para campo que não existe: o campo APARECE.
  //
  // A razão é a assimetria do dano. Esconder um campo obrigatório por engano
  // deixa o visitante com um formulário que não fecha e sem nada para corrigir —
  // ele perde o canal de contato. Mostrar um campo a mais é incômodo cosmético.
  // Entre os dois erros possíveis, este arquivo escolhe sempre o barato.
  if (!isConditionWellFormed(condition)) return true;

  const gatilho = fields.find(field => field?.name === condition.field);
  if (!gatilho) return true;

  const atual = resolveFieldValue(gatilho, values[condition.field]);

  if (gatilho.type === 'checkbox') {
    return evaluateBooleanCondition(condition, atual);
  }

  if (condition.operator === 'filled') return normalize(atual).length > 0;

  const alvo = fold(condition.value);
  const observado = fold(atual);

  if (condition.operator === 'is') return observado === alvo;
  if (condition.operator === 'is_not') return observado !== alvo;
  return observado.includes(alvo);
};

/**
 * Filtra a lista de campos pelo `show_if`.
 *
 * Campo escondido não é validado nem enviado — quem chama trabalha só sobre o
 * que esta função devolve. Sem isso, um condicional obrigatório e invisível
 * trava o envio para sempre.
 */
export const visibleFields = (fields = [], values = {}) =>
  fields.filter(field => evaluateCondition(field.show_if, values, fields));

/**
 * A etapa de um campo. Fora de 1..MAX_STEP, ou ausente, cai na etapa 1 —
 * de novo pela assimetria: campo com etapa inválida some da tela se a gente
 * confiar no número, e some sem nada avisar.
 */
export const stepOf = field => {
  const step = Number.parseInt(field?.step, 10);
  if (!Number.isFinite(step) || step < 1 || step > MAX_STEP) return 1;
  return step;
};

/** As etapas realmente ocupadas, ordenadas e sem repetição. */
export const stepsOf = (fields = []) =>
  [...new Set(fields.map(stepOf))].sort((a, b) => a - b);

/**
 * A posição do campo dentro da etapa.
 *
 * ESPELHA `preChatModel.js#positionOf`, incluindo a razão: campo SEM `position`
 * vai para o FIM, e não para a frente. A tela antiga não grava a chave, então um
 * formulário legado que ganha um campo ordenado mantém a ordem antiga e recebe o
 * novo no fim — que é o que quem configurou espera. Tratar ausência como zero
 * embaralharia o formulário inteiro na primeira reordenação.
 */
const positionOf = field =>
  Number.isFinite(Number(field?.position))
    ? Number(field.position)
    : Number.MAX_SAFE_INTEGER;

/**
 * Os campos de uma etapa, NA ORDEM DO PAINEL.
 *
 * `position` era gravado pelo painel, desenhava a ordem que o administrador vê
 * ao arrastar os campos — e o widget o ignorava, renderizando na ordem do array.
 * Arrastar um campo na tela de configuração não mudava nada no site do cliente.
 * Empate de `position` cai na ordem do array, que é a ordem da tela antiga.
 */
export const fieldsForStep = (fields = [], step = 1) =>
  fields
    .map((field, index) => ({ field, index }))
    .filter(({ field }) => stepOf(field) === step)
    .sort((a, b) => {
      const byPosition = positionOf(a.field) - positionOf(b.field);
      return byPosition !== 0 ? byPosition : a.index - b.index;
    })
    .map(({ field }) => field);

/**
 * Aplica a máscara do campo. Delega ao 3.13; máscara desconhecida, nula ou
 * vazia devolve o valor intacto — o schema aceita `null` e `''` de propósito.
 */
export const maskFieldValue = (value, field = {}) => {
  const mask = normalize(field.mask);
  if (!mask) return value;
  return applyMask(value, mask);
};

/**
 * Chave de i18n de cada código que o helper do 3.13 devolve.
 *
 * Mapa EXPLÍCITO em vez de interpolar o código na chave, e não é preciosismo: o
 * lint de i18n (`@intlify/vue-i18n/no-dynamic-keys`) não consegue conferir chave
 * montada em tempo de execução, então uma chave que não existisse em `pt_BR` ou
 * em `en` só apareceria como texto cru na tela do visitante. Escrita assim, cada
 * uma é verificável — e o teste de paridade das duas línguas passa a ter o que
 * comparar.
 */
const MESSAGE_KEYS = {
  REQUIRED: 'PRE_CHAT_FORM.VALIDATION.REQUIRED',
  CPF: 'PRE_CHAT_FORM.VALIDATION.CPF',
  CNPJ: 'PRE_CHAT_FORM.VALIDATION.CNPJ',
  CPF_CNPJ: 'PRE_CHAT_FORM.VALIDATION.CPF_CNPJ',
  CEP: 'PRE_CHAT_FORM.VALIDATION.CEP',
  UF: 'PRE_CHAT_FORM.VALIDATION.UF',
  EMAIL: 'PRE_CHAT_FORM.VALIDATION.EMAIL',
  CORPORATE_EMAIL: 'PRE_CHAT_FORM.VALIDATION.CORPORATE_EMAIL',
  PHONE: 'PRE_CHAT_FORM.VALIDATION.PHONE',
  JUNK_NAME: 'PRE_CHAT_FORM.VALIDATION.JUNK_NAME',
  JUNK_PHONE: 'PRE_CHAT_FORM.VALIDATION.JUNK_PHONE',
  JUNK_EMAIL: 'PRE_CHAT_FORM.VALIDATION.JUNK_EMAIL',
};

export const VALIDATION_MESSAGE_KEYS = MESSAGE_KEYS;

/**
 * O erro do campo, já resolvido em texto.
 *
 * Devolve `null` quando não há erro. O `code` que o 3.13 entrega é sufixo de
 * chave de i18n, nunca texto pronto — e `error_message` do campo, quando o
 * administrador escreveu um, vence o catálogo.
 *
 * @returns {?{message: string, severity: 'error'|'warning'}}
 */
export const fieldErrorFor = (field, value, { t } = {}) => {
  const alvo = field || {};
  const { valid, severity, code } = validateFieldValue(value, {
    validator: normalize(alvo.validator) || undefined,
    required: !!alvo.required,
  });

  if (valid) return null;

  const custom = normalize(alvo.error_message);
  // A mensagem do administrador não substitui o REQUIRED: ela foi escrita para
  // explicar o formato, e "Confira o CPF do titular" num campo vazio troca a
  // instrução certa por uma confusa.
  if (custom && code !== 'REQUIRED') return { message: custom, severity };

  // A chave sai de MESSAGE_KEYS, que e um mapa fechado e literal. O que o lint
  // nao consegue conferir aqui esta conferido por TESTE: `preChatFieldRules.spec.js`
  // exige cada uma das 12 chaves presente em pt_BR E em en. Silenciar sem esse
  // teste seria trocar um aviso por um texto cru na tela do visitante.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return { message: t(MESSAGE_KEYS[code]), severity };
};
