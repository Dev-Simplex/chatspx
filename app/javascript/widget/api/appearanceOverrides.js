import { API } from 'widget/helpers/axios';
import { buildAppearanceOverridesRequest } from 'widget/api/appearanceOverridesRequest';

/**
 * BLOCO 3.18 — o relatorio de precedencia, do widget para o servidor.
 *
 * POR QUE ISTO MORA NO IFRAME, E NAO NO HOST
 *
 * Mesma razao do 4.21: o fato acontece no host — e la que o `chatwootSettings`
 * do site existe —, mas o `sdk.js` tem teto de peso (A13) e e baixado por 100%
 * dos visitantes de todos os sites de todos os clientes. Aqui dentro ja existem
 * `axios`, o `X-Auth-Token` da sessao e o tratamento de erro. O host empurra a
 * lista pela ponte e paga so o `postMessage`.
 *
 * O QUE ESTA LISTA VIRA DO OUTRO LADO
 *
 * `inbox.additional_attributes.widget_appearance_overrides`, que a tela de
 * aparencia LE desde o bloco 3.09 (`AppearancePage.vue`) e que ate aqui
 * ninguem escrevia: `overriddenFields` era `[]` para sempre e o aviso de
 * override nunca aparecia. E o unico caminho pelo qual o painel pode saber o
 * que esta escrito no HTML do site do cliente.
 *
 * A URL VEM DE `appearanceOverridesRequest`, E ISSO NAO E CERIMONIA
 *
 * Ate a revisao deste bloco o caminho era uma constante crua, sem
 * `website_token`, e o servidor respondia 404 a toda chamada — o relatorio
 * nunca chegou. O modulo vizinho monta a requisicao inteira (URL e corpo), nao
 * importa nada, e por isso o request spec consegue EXECUTA-LO e mandar ao Rails
 * exatamente o que sai daqui. Ver o cabecalho dele.
 *
 * MELHOR ESFORCO, e a razao e a mesma do 4.18/4.21: nenhuma falha deste
 * relatorio pode aparecer para o visitante nem virar retentativa no site do
 * cliente. O pior caso de perde-lo e um aviso desatualizado no painel; o pior
 * caso de deixa-lo lancar e um erro no rastreador de erros do CLIENTE.
 */
export const registrarSobrescritasDoSite = ({ fields } = {}) => {
  // `undefined` e "o host nao mediu" e nao chega aqui (o `IFrameHelper` so
  // manda a mensagem quando o servidor entregou `widgetAppearance`). Lista
  // VAZIA, essa sim, precisa viajar: e o que apaga um aviso que ficou velho
  // depois de o cliente remover o `chatwootSettings` do site dele.
  const requisicao = buildAppearanceOverridesRequest({
    search: window.location.search,
    fields,
  });
  if (!requisicao) return Promise.resolve();

  return API.post(requisicao.url, requisicao.body).catch(() => {});
};

export default { registrarSobrescritasDoSite };
