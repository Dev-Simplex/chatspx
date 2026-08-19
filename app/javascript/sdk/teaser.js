/**
 * O TEASER — bloco 4.06. Vive no HOST, ao lado do lançador.
 *
 * PROJETADO CONTRA UM TETO, E O TETO APERTOU
 *
 * O plano chama este bloco de "o maior consumidor de bytes do host em todo o
 * plano". A folga do `sdk.js` medida logo após o merge é de **1.612 B gzip**,
 * não os 3.650 B do briefing — o merge acrescentou 2.038 B. Cada decisão aqui
 * foi tomada com esse número à vista:
 *
 *   · UM componente, DUAS formas (10º aceite). Discreto é o Chamativo com foto e
 *     chip ocultos por CSS. Dois componentes dobrariam o peso do arquivo que
 *     100% dos visitantes de todos os sites baixa, para entregar o menor.
 *   · ZERO dado novo na ponte. Foto, texto e tempo de resposta já viajam em
 *     `chatwootWebChannel` desde sempre (`avatarUrl`, `welcomeTagline`,
 *     `replyTime`). Nada de campo novo, nada de i18n duplicado no host.
 *   · Nenhuma biblioteca. DOM cru, com as helpers que o SDK já tem.
 *
 * O QUE NÃO ESTÁ AQUI, E POR QUÊ
 *
 * Nada de auto-open: os níveis `discreet` e `bold` **nunca** abrem o painel
 * sozinhos (aceite 4). O `aggressive` é o bloco 4.20 e mora fora deste arquivo.
 */
import { setCookieWithDomain } from './cookieHelpers';
import Cookies from 'js-cookie';

const COOKIE_DISPENSA = 'cw_teaser_dismissed';
// 30 dias, o mesmo prazo do estado de familiaridade (4.19).
const DIAS = 30;

// O gatilho é COMPOSTO: tempo E rolagem. Oito segundos sozinhos não disparam —
// é o aceite 1, e é o que separa "o visitante está lendo" de "o visitante
// abriu a aba e foi fazer outra coisa".
const SEGUNDOS = 8;
const ROLAGEM = 0.3;

const jaDispensou = () => Cookies.get(COOKIE_DISPENSA) === '1';

const marcarDispensa = baseDomain => {
  const expira = new Date();
  expira.setDate(expira.getDate() + DIAS);
  setCookieWithDomain(COOKIE_DISPENSA, '1', { expires: expira, baseDomain });
};

/**
 * Banner de cookies visível? Então o teaser não dispara (aceite 3).
 *
 * Dois balões disputando o canto inferior é ruim para o visitante e péssimo para
 * quem precisa aceitar o banner para navegar. A detecção é por heurística de
 * seletor — não há padrão para isso na web — e ela é DELIBERADAMENTE generosa:
 * na dúvida, não aparecer é o erro barato; aparecer por cima do banner é o caro.
 */
const bannerDeCookieVisivel = () => {
  const alvos = document.querySelectorAll(
    '[id*="cookie" i],[class*="cookie" i],[id*="consent" i],[class*="consent" i],[aria-label*="cookie" i]'
  );
  return [...alvos].some(el => {
    const r = el.getBoundingClientRect();
    if (r.width < 120 || r.height < 40) return false;
    const s = getComputedStyle(el);
    return (
      s.display !== 'none' && s.visibility !== 'hidden' && s.opacity !== '0'
    );
  });
};

/**
 * Monta o teaser e devolve uma função de limpeza — ou `null` quando ele não
 * deve existir.
 *
 * ⚠️ Aceite 8: com `teaserEnabled: false` o código **não é montado**, não é só
 * escondido. Por isso a checagem está aqui em cima, antes de qualquer `document.
 * createElement` e antes de registrar um único listener: com o teaser desligado
 * o host não paga DOM, não paga evento de scroll e não paga timer.
 */
export const montarTeaser = ({
  holder,
  canal = {},
  nivel = 'bold',
  baseDomain,
  aoAbrir,
  aoExibir,
  aoDispensar,
} = {}) => {
  if (!holder || canal.teaserEnabled === false) return null;
  if (nivel !== 'bold' && nivel !== 'discreet') return null;
  if (jaDispensou()) return null;

  const cartao = document.createElement('div');
  // `all: revert` no contêiner e prefixo `woot-` em tudo: o teaser vive FORA do
  // iframe, exposto ao CSS do site do cliente. É o mesmo padrão que o SVG do
  // lançador já usa.
  cartao.className = `woot-teaser woot-teaser--${nivel}`;
  cartao.setAttribute('role', 'status');

  const foto = document.createElement('img');
  foto.className = 'woot-teaser__foto';
  foto.src = canal.avatarUrl || '';
  foto.alt = '';
  foto.setAttribute('aria-hidden', 'true');

  const corpo = document.createElement('div');
  corpo.className = 'woot-teaser__corpo';

  const texto = document.createElement('p');
  texto.className = 'woot-teaser__texto';
  texto.textContent = canal.welcomeTagline || canal.welcomeTitle || '';

  corpo.appendChild(texto);

  // O "chip" do Chamativo: o tempo de resposta, que já viaja no canal. Só
  // aparece se o servidor mandou — chip vazio é ruído.
  if (canal.replyTime) {
    const chip = document.createElement('span');
    chip.className = 'woot-teaser__chip';
    chip.textContent = canal.replyTime;
    corpo.appendChild(chip);
  }

  const fechar = document.createElement('button');
  fechar.className = 'woot-teaser__fechar';
  fechar.type = 'button';
  // 44×44 no CSS — o aceite pede ≥ 32×32, e o alvo do Olark tem 9,8×9,8.
  fechar.setAttribute('aria-label', canal.teaserDismissLabel || 'Dispensar');
  fechar.textContent = '×';

  cartao.append(foto, corpo, fechar);

  let armado = false;
  let visivel = false;
  let segundosOk = false;
  let rolagemOk = false;

  const exibir = () => {
    if (visivel || !segundosOk || !rolagemOk) return;
    // Aceite 3, verificado no instante da exibição e não na montagem: o banner
    // pode aparecer depois dos 8 segundos.
    if (bannerDeCookieVisivel()) return;
    visivel = true;
    holder.appendChild(cartao);
    // Um quadro depois, para a transição de entrada ter estado inicial.
    requestAnimationFrame(() => cartao.classList.add('woot-teaser--visivel'));
    if (aoExibir) aoExibir();
  };

  const esconder = () => {
    if (!visivel) return;
    visivel = false;
    cartao.classList.remove('woot-teaser--visivel');
    cartao.classList.add('woot-teaser--saindo');
    setTimeout(() => cartao.remove(), 200);
  };

  const dispensar = evento => {
    if (evento) evento.stopPropagation();
    esconder();
    marcarDispensa(baseDomain);
    if (aoDispensar) aoDispensar();
  };

  const abrir = () => {
    esconder();
    if (aoAbrir) aoAbrir();
  };

  const aoRolar = () => {
    const alcance = document.documentElement.scrollHeight - window.innerHeight;
    // Página que não rola satisfaz a condição: exigir 30% de uma página de uma
    // tela só seria exigir o impossível, e o gatilho nunca dispararia.
    const proporcao = alcance <= 0 ? 1 : window.scrollY / alcance;
    if (proporcao >= ROLAGEM) {
      rolagemOk = true;
      window.removeEventListener('scroll', aoRolar);
      exibir();
    }
  };

  const relogio = setTimeout(() => {
    segundosOk = true;
    exibir();
  }, SEGUNDOS * 1000);

  fechar.addEventListener('click', dispensar);
  cartao.addEventListener('click', abrir);
  window.addEventListener('scroll', aoRolar, { passive: true });
  aoRolar();
  armado = true;

  return () => {
    if (!armado) return;
    clearTimeout(relogio);
    window.removeEventListener('scroll', aoRolar);
    cartao.remove();
  };
};
