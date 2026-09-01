/**
 * O que conta como "a rede caiu" — bloco 2.16.
 *
 * A fila só existe para o que vale a pena TENTAR DE NOVO. Um POST que não
 * chegou ao servidor vale; um POST que chegou e foi RECUSADO não. Confundir os
 * dois é o defeito clássico de fila offline: a mensagem que o servidor rejeitou
 * por regra de negócio volta a ser enviada a cada reconexão, para sempre, e o
 * visitante vê a mesma falha piscando pelo resto da sessão.
 *
 * A distinção do axios é objetiva e não depende de texto de mensagem: uma
 * resposta HTTP recebida — 4xx ou 5xx — preenche `error.response`. Uma queda de
 * rede, um DNS que não resolveu, um `ERR_CONNECTION_REFUSED` ou um timeout
 * deixam `response` vazio, com `request` preenchido (a requisição saiu, a
 * resposta não voltou).
 *
 * ── POR QUE NÃO BASTA `!error.response` ─────────────────────────────────────
 *
 * Porque um erro que estourou ANTES de a requisição sair também não tem
 * `response` — e não é rede, é defeito nosso. O caso não é hipotético: ele
 * apareceu montando o teste de tela deste bloco. `endPoints.sendMessage` lê
 * `window.WOOT_WIDGET.$root.$i18n.locale`; sem esse global, um `TypeError`
 * sobe do MONTADOR DA URL, antes de qualquer socket. Classificado como rede,
 * ele entraria na fila e seria reenviado a cada reconexão pelo resto da
 * sessão, falhando exatamente igual todas as vezes e travando a fila (que para
 * no item que falha, e faz certo em parar) — a mensagem seguinte do visitante
 * nunca sairia.
 *
 * Então exige-se PROVA de que a requisição saiu. O axios sempre a deixa: todo
 * erro de rede que ele fabrica — `ERR_NETWORK`, `ECONNABORTED` de timeout, DNS
 * que não resolveu — nasce com o `request` preenchido, porque foi o adaptador
 * quem o criou, depois de tentar. Um `TypeError` do nosso código não tem nem
 * `response`, nem `request`, nem `code`.
 *
 * `navigator.onLine === false` entra como prova independente: o navegador já
 * sabe que não há rede, e nesse estado nem o adaptador chega a tentar. Ele SOMA
 * e nunca filtra — `onLine` é notoriamente otimista, dizendo `true` para quem
 * está num Wi-Fi sem saída para a internet, então usá-lo como condição
 * necessária deixaria a fila vazia justamente no caso mais comum.
 */

/** Códigos com que o axios marca "não consegui falar com o servidor". */
const CODIGOS_DE_REDE = ['ERR_NETWORK', 'ECONNABORTED', 'ETIMEDOUT'];

export const isNetworkFailure = error => {
  // Resposta recebida = o servidor falou. Não é queda de rede, seja 422 ou 500,
  // e reenviar seria repetir para sempre uma recusa que já é definitiva.
  if (error?.response) return false;

  if (typeof navigator !== 'undefined' && navigator.onLine === false) {
    return true;
  }

  return Boolean(error?.request) || CODIGOS_DE_REDE.includes(error?.code);
};
