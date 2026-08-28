/*
 * Hash de DEDUPE do `setUser` — bloco 2.18, frente do `sdk.js`.
 *
 * POR QUE ESTE ARQUIVO EXISTE. `cookieHelpers.js` calculava este hash com o
 * pacote `md5`, e ele é o único consumidor de `md5` no repositório inteiro.
 * Medido com `chunk.modules` do Rollup (não com grep no bundle, que mente):
 * `md5` + `crypt` + `charenc` + `is-buffer` + os wrappers de CommonJS somavam
 * 11.687 B renderizados, e 5.562 B CRUS no `sdk.js` já minificado — 14% do
 * arquivo que 100% dos visitantes de todos os sites de todos os clientes
 * baixa (A13). O teto cru é 40.000 B e o arquivo estava em 42.969 B.
 *
 * O QUE ESTE HASH PRECISA SER, E O QUE ELE NÃO PRECISA SER. Ele responde uma
 * pergunta só, dentro do navegador do próprio visitante: "os dados que o site
 * está me passando agora são IGUAIS aos da última vez?". O valor vai para o
 * cookie `cw_user_<websiteToken>` e nunca sai dali — não autentica nada, não
 * viaja para o servidor, não é comparado com nada produzido em outro lugar. O
 * `identifier_hash` que de fato autentica é HMAC-SHA256 feito no BACKEND do
 * cliente e não passa por aqui. Ou seja: resistência a colisão adversária não
 * é requisito; resistência a colisão ACIDENTAL é, e 128 bits dão isso de
 * sobra.
 *
 * O ALGORITMO é o cyrb128: quatro acumuladores de 32 bits, cada um com uma
 * constante ímpar diferente, misturados entre si a cada caractere e de novo no
 * final. `Math.imul` faz a multiplicação de 32 bits com wraparound que o `*`
 * do JS não faz (o `*` promove para double e perde os bits altos). Ele existe
 * desde o ES6 e roda em todo navegador que o `target` desta build já assume —
 * a nota do `vite.lib.config.ts` sobre NÃO subir o target continua valendo, e
 * este arquivo não a força.
 *
 * O QUE MUDA PARA QUEM JÁ TEM O COOKIE. O hash antigo era MD5, o novo não é:
 * na primeira carga depois do deploy nenhum cookie existente vai bater, e o
 * SDK vai emitir UM `set-user` a mais por visitante já identificado. Isso é o
 * lado seguro do erro — identificar de novo é idempotente no servidor, deixar
 * de identificar não seria — e acontece uma vez só, porque logo em seguida o
 * cookie é regravado no formato novo.
 */
/*
 * `no-bitwise` desligado NESTE arquivo, e só nele. A regra existe para pegar
 * `&`/`|` digitados no lugar de `&&`/`||`; aqui os operadores de bit são o
 * assunto — `^`, `>>>` e `Math.imul` são o que mantém as contas dentro de 32
 * bits com wraparound. Reescrever isto sem eles não é possível, e desligar a
 * regra por arquivo é mais honesto que 23 comentários de linha.
 */
/* eslint-disable no-bitwise */

// As quatro constantes de mistura do cyrb128. São ímpares e sem estrutura
// decimal de propósito: constante par perderia bits baixos a cada `imul`.
const M1 = 597399067;
const M2 = 2869860233;
const M3 = 951274213;
const M4 = 2716044179;

const hex8 = value => (value >>> 0).toString(16).padStart(8, '0');

/**
 * 128 bits de hash não criptográfico, devolvidos como 32 caracteres hex
 * minúsculos — o mesmo formato que o MD5 devolvia, para que o valor do cookie
 * continue sendo uma string opaca do mesmo tamanho.
 *
 * @param {string} input
 * @returns {string} 32 caracteres em [0-9a-f]
 */
export const dedupeHash = input => {
  const text = String(input);
  // Sementes do SHA-2/BLAKE (frações de raízes quadradas de primos): valores
  // sem estrutura, para que a entrada vazia não produza um hash de zeros.
  let h1 = 1779033703;
  let h2 = 3144134277;
  let h3 = 1013904242;
  let h4 = 2773480762;

  for (let i = 0; i < text.length; i += 1) {
    // `charCodeAt` percorre por unidade UTF-16: um emoji entra como os dois
    // surrogates, e as duas metades participam do hash. É o que basta aqui —
    // o requisito é distinguir strings diferentes, não normalizar Unicode.
    const k = text.charCodeAt(i);
    h1 = h2 ^ Math.imul(h1 ^ k, M1);
    h2 = h3 ^ Math.imul(h2 ^ k, M2);
    h3 = h4 ^ Math.imul(h3 ^ k, M3);
    h4 = h1 ^ Math.imul(h4 ^ k, M4);
  }

  // Avalanche final: sem ela, uma diferença nos últimos caracteres da entrada
  // ficaria confinada aos bits altos de um dos acumuladores.
  h1 = Math.imul(h3 ^ (h1 >>> 18), M1);
  h2 = Math.imul(h4 ^ (h2 >>> 22), M2);
  h3 = Math.imul(h1 ^ (h3 >>> 17), M3);
  h4 = Math.imul(h2 ^ (h4 >>> 19), M4);
  h1 ^= h2 ^ h3 ^ h4;
  h2 ^= h1;
  h3 ^= h1;
  h4 ^= h1;

  return hex8(h1) + hex8(h2) + hex8(h3) + hex8(h4);
};
