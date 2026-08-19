/**
 * O `dataLayer` — bloco 5.10 (T-C4.7), regra **RC4**: publicar **sempre**.
 *
 * ESTE ARQUIVO É EAGER, e é o único pedaço da ponte de tags que está no `sdk.js`. A razão é o
 * padrão de fábrica do T-C4.10: quem não configurou destino nenhum **não tem tag nossa disparando
 * no site dele** — e, por isso mesmo, o artefato da ponte (`tracking.js`) nem chega a ser baixado.
 * Se o `push` morasse lá dentro, "somente `dataLayer`" seria um modo que ninguém consegue usar:
 * o cliente que integra por GTM — que é exatamente quem não cola Pixel ID nenhum aqui — ficaria
 * sem evento algum.
 *
 * São seis linhas de código eager, e elas não são novas: `tracking/consent.js` já publicava o
 * Consent Mode por este caminho. O que este arquivo faz é dar um nome ao que estava lá dentro,
 * para que a ponte e o consentimento empurrem pela MESMA porta — duas portas seriam duas formas
 * de o `window.dataLayer` do cliente ser substituído em vez de estendido.
 *
 * `window.dataLayer = window.dataLayer || []` é a regra **RC2** (código aditivo, nunca
 * destrutivo) na sua forma mais literal: reatribuir o array apagaria tudo o que o GTM do cliente
 * já enfileirou antes de nós — inclusive o `gtm.js` dele.
 */

/**
 * Empurra um objeto para o `dataLayer` do site.
 *
 * NUNCA LANÇA (T-C4.8): isto roda dentro do caminho de eventos do widget, no site do cliente, e
 * uma exceção aqui pode interromper as tags seguintes de um contêiner do GTM.
 *
 * Não devolve nada, e a ausência é deliberada: ninguém em produção verifica o resultado de um
 * `push` num array, e um `return` que só o teste leria é byte que 100% dos visitantes baixam.
 */
export const pushToDataLayer = payload => {
  try {
    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push(payload);
  } catch {
    // Site que congelou o `dataLayer` ou o substituiu por algo que não é array. Não há o que
    // fazer, e não há por que avisar: o console é do cliente.
  }
};
