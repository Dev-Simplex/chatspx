import { API } from 'widget/helpers/axios';

/**
 * A INSTRUMENTACAO DOS TRES NIVEIS — bloco 4.21.
 *
 * POR QUE ISTO MORA NO IFRAME, E NAO NO HOST
 *
 * O fato acontece no host: e la que o teaser aparece, que o visitante dispensa e
 * que o painel abre sozinho. Mas o `sdk.js` tem teto de peso (A13) e e baixado por
 * 100% dos visitantes de todos os sites de todos os clientes — e aqui dentro ja
 * existem `axios`, o `X-Auth-Token` da sessao e o tratamento de erro. O host
 * empurra o fato pela ponte e paga so o `postMessage`.
 *
 * O ORDINAL, E POR QUE ELE E O QUE IMPEDE CONTAR DUAS VEZES
 *
 * Ele e a ordem desta abordagem na vida deste navegador, e vem do cookie do 4.19 —
 * nao e identificador novo, e o contador que ja existia. No servidor ele vira a
 * `dedup_key`, e o indice unico `(account_id, name, dedup_key)` do 5.03 faz o
 * resto: reenvio da mesma requisicao, visitante que manda tres mensagens seguidas,
 * retry de rede — tudo colapsa numa linha so. Sem ele, a derivacao padrao usaria
 * `occurred_at.to_i`, que distingue mal dois fatos no mesmo segundo e colapsa
 * visitantes diferentes da mesma conta.
 *
 * O CONTEXTO FICA GUARDADO porque a CONVERSAO nasce aqui dentro: quem sabe que o
 * visitante enviou mensagem e o `ChatFooter`, e ele precisa saber com que nivel
 * essa mensagem foi conquistada.
 */
const CAMINHO = '/api/v1/widget/approach_events';

let abordagem = null;

const enviar = stage => {
  // Sem abordagem nesta pagina nao ha o que atribuir: quem abriu o painel pelo
  // lancador nao converteu POR uma abordagem, e contar isso como conversao de um
  // nivel inflaria justamente o numero que este bloco existe para tornar confiavel.
  if (!abordagem) return Promise.resolve();

  return API.post(CAMINHO, { stage, ...abordagem }).catch(() => {
    // Melhor esforco, como o 4.18: nenhuma falha de telemetria pode aparecer para
    // o visitante nem virar retentativa no site do cliente.
  });
};

/** Chamado pela ponte, com o que o host mediu. */
export const registrarEtapaDaAbordagem = ({
  etapa,
  approach,
  approach_configured: approachConfigured,
  ordinal,
}) => {
  if (etapa === 'shown') {
    abordagem = {
      approach,
      approach_configured: approachConfigured,
      ordinal,
    };
  }

  return enviar(etapa);
};

export const registrarConversaoDaAbordagem = () => enviar('converted');

export default { registrarEtapaDaAbordagem, registrarConversaoDaAbordagem };
