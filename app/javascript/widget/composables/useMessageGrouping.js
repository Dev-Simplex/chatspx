import { computed, toValue } from 'vue';
import { MESSAGE_TYPE } from 'widget/helpers/constants';
import { isASubmittedFormMessage } from 'shared/helpers/MessageTypeHelper';

/**
 * Agrupamento visual das mensagens, como DADOS.
 *
 * Antes isto era CSS: seis seletores de irmão adjacente em `_conversation.scss`
 * (`.agent-message-wrap + .user-message-wrap` e companhia) decidiam a margem e
 * o canto "quebrado" de cada balão. Seletor de irmão adjacente é uma regra que
 * o componente não enxerga: ele não sabe se é continuação nem consegue ser
 * testado sem montar a lista inteira e ler CSS computado.
 *
 * As seis regras se reduzem a UMA, e é ela que este módulo implementa:
 *
 *   se o autor FINAL da linha anterior é o mesmo autor INICIAL desta linha,
 *   então esta linha continua o grupo; senão, começa um bloco novo.
 *
 * "Autor final" e "autor inicial" não são a mesma coisa porque uma mensagem de
 * agente pode terminar com uma fala do visitante embutida — resposta a
 * `input_select`, e-mail capturado, formulário enviado. É o que o antigo
 * `.has-response` marcava na marra.
 */
export const AUTOR = { AGENTE: 'agente', VISITANTE: 'visitante' };

const atributos = message => message?.content_attributes || {};

const ehDoVisitante = message =>
  message?.message_type === MESSAGE_TYPE.INCOMING;

/**
 * A mensagem do agente carrega uma resposta já dada pelo visitante?
 *
 * Espelha `AgentMessage.hasRecordedResponse`: quando o backend materializou a
 * resposta como mensagem própria (`reply_message_id`), ela vem pela lista e o
 * balão local seria duplicata.
 */
export const temRespostaEmbutida = message => {
  const attrs = atributos(message);
  if (attrs.reply_message_id) return false;

  const contentType = message?.content_type || '';
  return Boolean(
    attrs.submitted_email ||
      (attrs.submitted_values && !['form', 'input_csat'].includes(contentType))
  );
};

export const ehFormularioRespondido = message =>
  !atributos(message).reply_message_id && isASubmittedFormMessage(message);

/**
 * De quem é a LINHA — o que o CSS antigo expressava como `.agent-message-wrap`
 * contra `.user-message-wrap`.
 *
 * Repare que não é "quem fala primeiro": uma linha de formulário respondido é
 * do agente e mesmo assim abre desenhando os valores do visitante. Usar o
 * autor visível aqui pareceria mais correto e MUDARIA o agrupamento dessa
 * linha — e o aceite do bloco é agrupamento visualmente idêntico. A semântica
 * antiga é a que vale; a diferença está anotada em teste para quem vier depois
 * não a "corrigir" sem querer.
 */
export const tipoLinha = message =>
  ehDoVisitante(message) ? AUTOR.VISITANTE : AUTOR.AGENTE;

/** Quem fala por último na linha. */
export const autorFinal = message => {
  if (ehDoVisitante(message)) return AUTOR.VISITANTE;
  return temRespostaEmbutida(message) || ehFormularioRespondido(message)
    ? AUTOR.VISITANTE
    : AUTOR.AGENTE;
};

/**
 * Calcula o agrupamento de uma lista já ordenada.
 * Devolve um mapa `id -> { continuaGrupo, autorInicial, autorFinal }`.
 */
export const calcularAgrupamento = (messages = []) => {
  const mapa = {};
  messages.forEach((message, indice) => {
    const anterior = messages[indice - 1];
    mapa[message.id] = {
      tipoLinha: tipoLinha(message),
      autorFinal: autorFinal(message),
      // A regra única que substitui os seis seletores de irmão adjacente.
      continuaGrupo: anterior
        ? autorFinal(anterior) === tipoLinha(message)
        : false,
    };
  });
  return mapa;
};

export function useMessageGrouping(messages) {
  // `toValue` aceita ref, getter e valor puro — o chamador não precisa saber
  // qual dos três este composable espera.
  const agrupamento = computed(() =>
    calcularAgrupamento(toValue(messages) || [])
  );

  const agrupamentoDe = id =>
    agrupamento.value[id] || {
      tipoLinha: AUTOR.AGENTE,
      autorFinal: AUTOR.AGENTE,
      continuaGrupo: false,
    };

  return { agrupamento, agrupamentoDe };
}
