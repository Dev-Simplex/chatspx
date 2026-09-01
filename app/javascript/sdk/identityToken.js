/**
 * Bloco 5.19 — o PRODUTOR do `identity_token` no cliente.
 *
 * O servidor sabia ler o JWT desde a primeira entrega deste bloco
 * (`app/services/widget/identity_token_service.rb` + `contacts_controller.rb`), mas nao havia
 * ninguem do lado do navegador que o produzisse: a allowlist de `buildContactPayload` descartava
 * o campo em silencio, e o formato novo era, na pratica, inalcancavel pelo produto. Este arquivo
 * fecha esse buraco.
 *
 * POR QUE CALLBACK, E NAO UM CAMPO. O JWT tem `exp` obrigatorio — e obrigatorio de proposito,
 * porque token sem validade vazado vale para sempre. Um campo estatico (`chatwootSettings.token`
 * ou `data-identity-token` no snippet) e o oposto disso:
 *
 *   · o snippet e HTML, aparece no view-source e entra em cache de CDN — e por isso que
 *     `snippetConfig.js` (5.18) ja RECUSA identidade e credencial por `data-*`;
 *   · uma SPA que fica aberta o dia inteiro veria o token expirar e nao teria como renova-lo:
 *     o valor foi lido uma vez, no boot, e ninguem pergunta de novo.
 *
 * Com callback, quem responde e o site, no instante da identificacao. Ele pode devolver um valor
 * em memoria, ler um cookie do proprio dominio ou ir buscar no backend dele — e uma renovacao
 * feita depois do boot chega sozinha na chamada seguinte.
 *
 * O CONTRATO, e as tres coisas que ele NAO faz:
 *
 *   1. NAO LANCA. Um provedor que estoura (backend fora do ar, `await` que rejeita) NAO pode
 *      derrubar `setUser`. O aceite do bloco diz que token invalido degrada para anonimo, e nao
 *      para erro — a falha do provedor e o mesmo caso, so que do lado de ca.
 *   2. NAO INSISTE. Sem retry, sem timeout proprio, sem fila. Se a promessa do site demorar, a
 *      identificacao espera por ela — e essa espera e do site, que e quem sabe o proprio SLA.
 *   3. NAO GUARDA. Nada de cache do token aqui: quem decide validade e `exp`, e o cache seria uma
 *      segunda fonte de verdade sobre uma credencial. O provedor e chamado a cada identificacao.
 *
 * E o silencio tambem foi decidido: falhar sem dizer nada seria repetir o defeito que o 1.23
 * fechou. Por isso `resolveIdentityToken` recebe `aoFalhar` e o entrypoint liga esse gancho ao
 * mesmo `chatwoot:error` que o resto da API publica ja usa.
 */

let provedor = null;

/**
 * Registra (ou desregistra) o callback. Vale IMEDIATAMENTE — nao passa pela fila pre-boot do
 * 1.23, porque nao e um despacho para o painel: e estado local do host. Registrar antes do
 * `run()` ou logo depois dele da no mesmo, contanto que aconteca antes do drenar da fila.
 *
 * Qualquer coisa que nao seja funcao desregistra em vez de guardar lixo — assim
 * `setIdentityTokenProvider(null)` e a forma documentada de desligar (logout no site do cliente).
 *
 * @param {Function|null} fn
 */
export const setIdentityTokenProvider = fn => {
  provedor = typeof fn === 'function' ? fn : null;
};

const conferir = token => {
  // Devolver nada e resposta LEGITIMA, nao falha: e o visitante que ainda nao entrou no site do
  // cliente. Reportar isso como erro encheria o `chatwoot:error` de ruido em toda pagina publica
  // de um site que so identifica quem esta logado.
  if (!token) return undefined;

  // Forma errada, porem, e engano de quem integra, e sobre isso o SDK nao pode ser mudo: um
  // objeto `{ token: '...' }` devolvido por engano viraria `[object Object]` no corpo da
  // requisicao e o servidor responderia "invalido" — longe daqui, sem dizer por que.
  if (typeof token !== 'string') {
    // Mensagem curta de proposito: cada byte do `sdk.js` e baixado por 100% dos visitantes de
    // todos os sites (teto A13). O nome do metodo + "string" ja diz o que fazer.
    throw new Error('identityTokenProvider: o JWT tem de ser string');
  }

  return token;
};

/**
 * Pergunta ao site qual e o token AGORA.
 *
 * NAO E `async`, E ISSO E O PONTO. Uma funcao `async` devolve promessa sempre — inclusive quando
 * a resposta ja esta pronta —, e uma promessa gratuita aqui QUEBRA UM CONTRATO de outro bloco: a
 * fila pre-boot (1.23) preserva a ordem de chegada porque cada despacho emite a sua mensagem no
 * mesmo tick em que e chamado. Com um `await` no caminho do `setUser`, o `set-user` passava a
 * sair DEPOIS do `set-label` enfileirado atras dele — medido, e vermelho em
 * `preBootQueue.spec.js`. Devolvendo valor cru quando ele existe, o caso comum (sem provedor, ou
 * provedor sincrono) continua sincrono e a ordem fica intacta.
 *
 * Quem chama trata as duas formas com `entao`, logo abaixo.
 *
 * @param {Function} [aoFalhar] recebe o erro quando o provedor estoura ou devolve forma errada
 * @returns {string|undefined|Promise<string|undefined>} o JWT, ou nada quando nao ha credencial
 */
export const resolveIdentityToken = aoFalhar => {
  if (!provedor) return undefined;

  const falhou = erro => {
    aoFalhar?.(erro);
    return undefined;
  };

  try {
    const bruto = provedor();
    // So o provedor assincrono adia. E ele adia porque o SITE escolheu ir buscar o token em
    // algum lugar — a espera e do integrador, que e quem conhece o proprio SLA.
    return bruto && typeof bruto.then === 'function'
      ? bruto.then(conferir).catch(falhou)
      : conferir(bruto);
  } catch (erro) {
    return falhou(erro);
  }
};

/**
 * Aplica `fn` AGORA quando o valor ja esta pronto, e so depois quando ele e promessa.
 *
 * Existe para nao transformar em assincrono um caminho que era sincrono — ver o paragrafo sobre
 * a ordem da fila em `resolveIdentityToken`. Um `Promise.resolve(x).then(fn)` faria o trabalho,
 * mas custaria exatamente o tick que este bloco precisa nao gastar.
 */
export const entao = (valor, fn) =>
  valor && typeof valor.then === 'function' ? valor.then(fn) : fn(valor);

// So para os testes: devolve o registro ao estado inicial entre cenarios.
export const resetarProvedorParaTestes = () => {
  provedor = null;
};
