/**
 * A DEGRADACAO POR FAMILIARIDADE — bloco 4.19.
 *
 * O QUE O COOKIE GUARDA, E SO ISSO
 *
 * Duas coisas: quantas vezes ja abordamos este navegador, e se ele ja converteu.
 * Nada de perfil de navegacao, nada de identificador novo — a arbitragem A15 e
 * explicita: "guardar contagem de abordagem por visitante no servidor criaria uma
 * tabela nova, um identificador novo e um problema de LGPD, para resolver o que um
 * cookie de primeira parte resolve".
 *
 * Formato `"<abordagens>.<0|1>"`. E legivel por quem abrir o DevTools no site do
 * cliente, o que e proposital: o visitante esta VENDO o teaser, e o estado que
 * decide o proximo nao pode ser mais opaco que o efeito dele.
 *
 * A escada, e por que ela e um array
 *
 *   aggressive -> bold -> discreet -> nada
 *
 * Descer um degrau e somar 1 ao indice; cair da escada e `undefined`, que vira
 * `null` — "nao aborde". Um `switch` de tres casos custaria mais bytes e diria a
 * mesma coisa pior. E o `sdk.js` tem teto (A13).
 *
 * NAO HA `Date.now()` AQUI. O prazo do cookie e o unico relogio: 30 dias sem
 * abordagem e o estado some, e o visitante volta a ser novo. Guardar timestamp
 * seria uma terceira informacao, e o aceite diz DUAS.
 */
import Cookies from 'js-cookie';
import { setCookieWithDomain } from '../cookieHelpers';

const COOKIE = 'cw_approach';
const SESSAO = 'cw_auto_open';
const DIAS = 30;
const NIVEIS = ['aggressive', 'bold', 'discreet'];

/**
 * Devolve `[abordagens, converteu]` — array, e nao objeto, porque nome de
 * propriedade sobrevive a minificacao e nome de variavel local nao. No arquivo
 * que 100% dos visitantes de todos os sites baixam, isso e um criterio.
 */
export const lerAbordagem = () => {
  const [n, c] = `${Cookies.get(COOKIE) || ''}`.split('.');
  return [+n || 0, c === '1'];
};

export const gravarAbordagem = (abordagens, converteu, baseDomain) =>
  setCookieWithDomain(COOKIE, `${abordagens}.${converteu ? 1 : 0}`, {
    expires: DIAS,
    baseDomain,
  });

/** O nivel efetivo depois de `degraus` abordagens sem conversao. */
export const degradar = (nivel, degraus) =>
  NIVEIS[NIVEIS.indexOf(nivel) + degraus] || null;

/**
 * O AUTO-OPEN E OPT-IN, E ACONTECE UMA VEZ POR SESSAO — bloco 4.20.
 *
 * Devolve `true` na primeira chamada da sessao e `false` depois. `sessionStorage`
 * e nao cookie por dois motivos, e o segundo e o que decide:
 *
 *  1. e literalmente um armazenamento de SESSAO — nao ha data de expiracao para
 *     calcular nem para errar;
 *  2. cookie viaja em TODA requisicao ao dominio do cliente. Um marcador que o
 *     servidor nunca le nao tem por que ser anexado a cada imagem e a cada folha
 *     de estilo do site que nos hospeda.
 *
 * `sessionStorage` e por ABA, e nao por navegador — o que abriria uma vez em cada
 * aba. O freio entre abas ja existe e e o cookie do 4.19: a primeira aba grava a
 * abordagem, a segunda le o contador e cai para `bold`. Com `degrade_on_return:
 * false` o administrador desligou esse freio de proposito, e ai abre em cada aba.
 *
 * O `try` nao e decoracao: `sessionStorage` LEVANTA (nao devolve null) quando o
 * site nos hospeda num iframe sem `allow-same-origin` ou com cookies de terceiros
 * bloqueados. Sem ele, o boot do SDK morre no site do cliente. Na duvida,
 * `false` — nao abrir e o erro barato.
 */
export const podeAbrirSozinho = () => {
  try {
    if (sessionStorage.getItem(SESSAO)) return false;
    sessionStorage.setItem(SESSAO, '1');
    return true;
  } catch (erro) {
    return false;
  }
};
