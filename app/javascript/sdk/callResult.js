/**
 * Resultado tipado das chamadas da API publica — bloco 5.17 (T-I4.1, camada A).
 *
 * O PROBLEMA. Ate aqui os metodos de dados devolviam `Promise<undefined>`: quem integra recebia
 * "terminou" e nada mais. As tres coisas que ele precisa distinguir ficavam indistinguiveis entre
 * si — a chamada saiu agora, a chamada esperou o boot, e a chamada nao fez nada porque os dados
 * eram identicos aos da ultima vez. As tres resolviam com o mesmo `undefined`.
 *
 * O caso mais caro e o terceiro. `setUser` deduplica por cookie (`computeHashForUserData`): se o
 * hash bate, ele retorna cedo e NAO manda mensagem nenhuma. Do lado de fora isso era
 * indistinguivel de sucesso — um integrador depurando "por que o contato nao atualizou?" nao tinha
 * como ver que a propria SDK tinha decidido nao mandar.
 *
 * O FORMATO. Objeto simples e congelado, com `status` sempre presente. Congelado porque ele
 * atravessa para o `window` do site: o script de terceiro da pagina do cliente nao muda o
 * resultado de quem chamou antes dele.
 *
 * ESCRITO PARA CABER, e o numero explica a forma. Este modulo entra no `sdk.js`, que tem teto de
 * bytes (A13) e ja estava ACIMA do limite CRU quando este bloco comecou: 40,60 KB contra 40 KB,
 * medidos com o build de producao (`vite.lib.config.ts`) sem uma linha daqui. O estouro nao e
 * deste bloco e nao cabe a ele consertar — esta REGISTRADO, com numero, para nao virar herança
 * silenciosa.
 *
 * O que cabe a este bloco e nao piorar de graca. Tres funcoes irmas com objeto de opcoes custavam
 * 680 B no artefato; este construtor unico com argumentos posicionais custa 580 B. Comentario nao
 * pesa — o terser o remove, e `grep -c '/\*' public/packs/js/sdk.js` da 0 —, codigo pesa.
 *
 * O QUE ESTE MODULO NAO TEM, e a ausencia e declarada. O T-I4.1 nomeia tambem "rejeitado por
 * confianca", "rejeitado por limite" e "chaves sem definicao correspondente". Os tres sao decisao
 * do SERVIDOR, e o caminho de volta nao existe: `IFrameHelper.sendMessage` e `postMessage` sem
 * resposta, e o unico retorno que o painel produz hoje (`IFrameHelper.events.error`) nao carrega
 * identificador de chamada, entao nao ha como correlacionar a recusa com a chamada que a causou.
 * Declarar as constantes sem nada que as produza seria a mesma assercao no vacuo que este bloco
 * existe para consertar. Elas entram quando o `callId` de ida e volta entrar junto.
 */

export const STATUS_ACEITO = 'accepted';
export const STATUS_ENFILEIRADO = 'queued';
export const STATUS_DEDUPLICADO = 'deduplicated';
export const STATUS_REJEITADO_VALIDACAO = 'rejected_validation';

/**
 * O resultado de uma chamada despachada.
 *
 * `queued` diz se ela ESPEROU o boot antes de sair, e vira o proprio `status`: e fato observavel e
 * util. Quem chama `setUser` junto com `run()` num container do GTM recebe `queued` e sabe que a
 * identidade so viajou quando o iframe ficou pronto, sem instrumentar nada.
 *
 * `deduplicado` NAO e erro — e a otimizacao funcionando —, e por isso vira resultado resolvido em
 * vez de rejeicao. Ele vence `queued` no `status` porque responde a pergunta mais urgente: nao
 * "quando saiu", mas "nao saiu".
 */
export const resultado = (method, queued, repetido) => {
  let status = queued ? STATUS_ENFILEIRADO : STATUS_ACEITO;
  if (repetido) status = STATUS_DEDUPLICADO;

  return Object.freeze({
    status,
    method,
    queued: !!queued,
    ...(repetido ? { reason: 'identical to the last payload' } : {}),
  });
};

/**
 * A validacao recusou a chamada. O resultado tipado e ANEXADO ao erro em vez de substitui-lo:
 * quem ja tratava `err.message` continua funcionando, e quem quiser ramificar por `status` passa a
 * conseguir sem comparar texto de mensagem.
 */
export const anexarRejeicao = (method, erro) => {
  if (erro && typeof erro === 'object') {
    erro.result = Object.freeze({
      status: STATUS_REJEITADO_VALIDACAO,
      method,
      reason: erro.message || String(erro),
    });
  }
  return erro;
};
