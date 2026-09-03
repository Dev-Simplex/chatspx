/**
 * Origem confiável do `postMessage` — lado do WIDGET (dentro do iframe).
 *
 * O widget não conhece, em tempo de build, a origem do site que o embute. A única
 * fonte que o NAVEGADOR fornece — e que o JavaScript de outra página não consegue
 * forjar — é o `document.referrer` do documento do iframe: quando o SDK executa
 * `iframe.src = …`, o navegador manda o `Referer` da página que embute, e é ele
 * que vira `document.referrer` aqui dentro.
 *
 * Quando o site declara `Referrer-Policy: no-referrer` (ou há downgrade
 * https→http), o referrer chega vazio e NÃO existe fonte confiável de origem.
 * Nesse caso mantemos o comportamento de hoje (aceitar a mensagem / enviar com
 * `'*'`) em vez de derrubar o widget: o bloco fecha a porta onde dá para fechar,
 * e deixa explícito onde não dá. Endurecer isso exige o SDK declarar a própria
 * origem na URL do iframe, o que é matéria de outro bloco.
 */

export const isRNWebView = () => Boolean(window.ReactNativeWebView);

export const getParentOrigin = () => {
  const referrer = document.referrer;
  if (!referrer) return null;
  try {
    return new URL(referrer).origin;
  } catch (error) {
    // referrer que não é URL absoluta: não dá para derivar origem.
    return null;
  }
};

/**
 * `true` quando a mensagem pode ser atendida. Uma origem conhecida e diferente
 * da do embutidor é descartada — é o caso do `postMessage` direto ao iframe,
 * hoje a via aberta que este bloco fecha.
 */
export const isTrustedOrigin = origin => {
  // React Native WebView entrega a mensagem sem origem real; não há o que comparar.
  if (isRNWebView()) return true;
  const parentOrigin = getParentOrigin();
  if (!parentOrigin) return true;
  return origin === parentOrigin;
};

/** `targetOrigin` do `postMessage` de saída — nunca `'*'` quando dá para saber. */
export const getParentTargetOrigin = () => getParentOrigin() || '*';
