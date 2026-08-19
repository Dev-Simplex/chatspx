/**
 * O emissor dos eventos de `window` — bloco 5.04.
 *
 * ── POR QUE ELE EXISTE, EM VEZ DE CADA LUGAR CHAMAR `sendMessage` ────────────
 *
 * Antes deste bloco havia três emissores espalhados (`ChatFooter.vue`,
 * `TeamAvailability.vue`, `actionCable.js`), cada um montando o envelope
 * `{ event: 'onEvent', eventIdentifier, data }` na mão. Três cópias do mesmo
 * formato é o começo de três formatos.
 *
 * Aqui o envelope é um só, e ele passa por duas guardas que a cópia manual não
 * tinha:
 *
 *  1. **FILTRO DE CONTRATO.** Só as chaves declaradas em `SDK_EVENT_CONTRACT`
 *     atravessam. O `window` do site do cliente é legível por QUALQUER script
 *     da página, inclusive de terceiro; a regra dura de
 *     `24-plano-backend-dados.md` §17.1 é "nome de campo sim, valor de PII
 *     nunca". Um `email` que escape para dentro do payload por descuido é
 *     descartado aqui, e o descarte é reportado — porque é defeito nosso.
 *  2. **NUNCA LANÇA.** O emissor roda dentro de ação de store, no meio do
 *     caminho do visitante. Um `postMessage` que falhe (frame morto, origem
 *     recusada) não pode impedir a conversa de ser criada. É a mesma doutrina
 *     do `TrackingEventListener` do 5.03: observabilidade não quebra o produto.
 *
 * ── E POR QUE "UMA VEZ" MORA AQUI, E NÃO NO COMPONENTE ───────────────────────
 *
 * O aceite do bloco manda emitir do STORE, nunca do componente. O motivo é de
 * ciclo de vida: componente monta e desmonta a cada troca de rota, então um
 * evento emitido de `mounted` dispara duas vezes num re-render e zero vez numa
 * navegação que reusa a instância. Este módulo vive enquanto o documento do
 * painel vive — mesmo tempo do store — e o conjunto `jaEmitidos` é o que
 * garante o "uma vez" do aceite.
 */
import { IFrameHelper } from 'widget/helpers/utils';
import {
  CHATWOOT_LEAD_IDENTIFIED,
  SDK_EVENT_CONTRACT,
} from 'widget/constants/sdkEvents';
import { reportWidgetError } from 'widget/helpers/telemetry';

const jaEmitidos = new Set();

/**
 * Devolve só as chaves que o contrato declara para este evento, na ordem do
 * contrato, e ignora as ausentes (evento com campo opcional vazio sai sem a
 * chave, não com `undefined` — `postMessage` descartaria o `undefined` de
 * qualquer jeito, e uma chave que às vezes existe é pior que uma que nunca
 * existe).
 *
 * Evento sem entrada no contrato passa INTACTO: os sete nomes antigos
 * (`chatwoot:on-message`, `chatwoot:postback`, …) já estão em produção com
 * payloads que este bloco não inventou e não pode estreitar.
 */
export const filterByContract = (eventName, data = {}) => {
  const contrato = SDK_EVENT_CONTRACT[eventName];
  if (!contrato) return data;

  const permitidas = {};
  contrato.payload.forEach(chave => {
    if (data?.[chave] !== undefined) permitidas[chave] = data[chave];
  });

  const descartadas = Object.keys(data || {}).filter(
    chave => !contrato.payload.includes(chave)
  );
  if (descartadas.length) {
    // Não é `console.warn` engolido: é defeito de quem chamou, e o único jeito
    // de descobrir que uma chave está sendo perdida no site de um cliente é
    // contá-la. A telemetria já deduplica e tem teto por sessão.
    reportWidgetError(
      new Error(
        `payload fora do contrato em ${eventName}: ${descartadas.join(', ')}`
      ),
      { origem: 'sdkEventEmitter' }
    );
  }

  return permitidas;
};

/**
 * Emite o evento para o SDK, que o repassa ao `window` do site
 * (`IFrameHelper.events.onEvent` → `dispatchWindowEvent`).
 *
 * @returns {boolean} `true` quando a mensagem saiu.
 */
export const emitSdkEvent = (eventName, data = {}) => {
  try {
    IFrameHelper.sendMessage({
      event: 'onEvent',
      eventIdentifier: eventName,
      data: filterByContract(eventName, data),
    });
    return true;
  } catch (error) {
    reportWidgetError(error, { origem: 'sdkEventEmitter' });
    return false;
  }
};

/**
 * Emite no máximo uma vez por `chave` na vida deste documento.
 *
 * A marcação é feita DEPOIS do envio bem-sucedido: um `postMessage` que falhou
 * não aconteceu, e marcar antes deixaria o evento perdido para sempre.
 *
 * @returns {boolean} `true` quando esta chamada foi a que emitiu.
 */
export const emitSdkEventOnce = (eventName, data = {}, chave = eventName) => {
  if (jaEmitidos.has(chave)) return false;

  const saiu = emitSdkEvent(eventName, data);
  if (saiu) jaEmitidos.add(chave);
  return saiu;
};

export const hasEmitted = chave => jaEmitidos.has(chave);

// Só para teste — ver o mesmo padrão em `helpers/telemetry.js`. Em produção o
// estado morre com o documento do painel: `reset()` recria o iframe.
// eslint-disable-next-line no-underscore-dangle
export const __resetSdkEventsForTests = () => jaEmitidos.clear();

// ─────────────────────────────────────────────────────────────────────────────
// `lead-identified`, que é o único evento deste bloco cujo PAYLOAD é uma regra
// de negócio e não uma cópia do que a API devolveu.
//
// O fato é "o contato passou a ter e-mail OU telefone" (T-C3.7). O que sai para
// o `window` são os NOMES dos identificadores que passaram a existir — nunca os
// valores. Quem precisa do valor é o servidor, que hasheia antes de mandar à
// Meta (regra RC5; ver `docs/tracking/contrato-de-eventos.md` §6 ponto 3).
// ─────────────────────────────────────────────────────────────────────────────

export const LEAD_IDENTIFIER_KEYS = Object.freeze(['email', 'phone_number']);

export const leadIdentifiers = (contact = {}) =>
  LEAD_IDENTIFIER_KEYS.filter(
    chave =>
      typeof contact?.[chave] === 'string' && contact[chave].trim() !== ''
  );

/**
 * Emite `chatwoot:lead-identified` no máximo uma vez por documento do painel.
 *
 * Devolve `false` — sem emitir — quando o contato ainda não tem identificador
 * nenhum. É por isso que a chamada pode ficar solta no caminho feliz de várias
 * ações: quem decide se o fato aconteceu é esta função, não o chamador.
 */
export const emitLeadIdentified = ({ contact, conversationId } = {}) => {
  const identifiers = leadIdentifiers(contact);
  if (!identifiers.length) return false;

  return emitSdkEventOnce(
    CHATWOOT_LEAD_IDENTIFIED,
    { conversation_id: conversationId, identifiers },
    CHATWOOT_LEAD_IDENTIFIED
  );
};
