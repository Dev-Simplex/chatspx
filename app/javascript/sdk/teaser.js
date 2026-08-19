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
 * O QUE MUDOU COM O 4.20, E POR QUE MUDOU AQUI
 *
 * O `aggressive` **abre o painel sozinho**, e o aceite manda que ele respeite o
 * MESMO gatilho composto do teaser. Um segundo relógio, um segundo listener de
 * rolagem e uma segunda detecção de banner de cookie seriam três chances de os
 * dois níveis divergirem — e o dobro de bytes no arquivo com teto (A13).
 *
 * Então o gatilho saiu de dentro do teaser e virou `armarGatilho`, que os três
 * níveis consomem. `montarTeaser` continua sendo a porta única: é lá que moram as
 * duas recusas que valem para os três (`teaserEnabled: false` e dispensa
 * persistida), e uma porta só é o que impede o Agressivo de escapar delas.
 */
import { setCookieWithDomain } from './cookieHelpers';
import Cookies from 'js-cookie';
import { podeAbrirSozinho } from './tracking/approach';

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
 * O GATILHO COMPOSTO — 8 s **E** 30 % de rolagem, uma vez só.
 *
 * Chama `quandoDisparar` no instante em que as duas condições valem, e devolve a
 * função de limpeza. O banner de cookie é conferido no INSTANTE do disparo, não
 * na montagem: ele pode aparecer depois dos 8 segundos (aceite 3 do 4.06).
 */
const armarGatilho = quandoDisparar => {
  let disparou = false;
  let segundosOk = false;
  let rolagemOk = false;

  const tentar = () => {
    if (disparou || !segundosOk || !rolagemOk || bannerDeCookieVisivel())
      return;
    disparou = true;
    quandoDisparar();
  };

  const aoRolar = () => {
    const alcance = document.documentElement.scrollHeight - window.innerHeight;
    // Página que não rola satisfaz a condição: exigir 30% de uma página de uma
    // tela só seria exigir o impossível, e o gatilho nunca dispararia.
    const proporcao = alcance <= 0 ? 1 : window.scrollY / alcance;
    if (proporcao >= ROLAGEM) {
      rolagemOk = true;
      window.removeEventListener('scroll', aoRolar);
      tentar();
    }
  };

  const relogio = setTimeout(() => {
    segundosOk = true;
    tentar();
  }, SEGUNDOS * 1000);

  window.addEventListener('scroll', aoRolar, { passive: true });
  aoRolar();

  return () => {
    clearTimeout(relogio);
    window.removeEventListener('scroll', aoRolar);
  };
};

/**
 * Monta a abordagem e devolve uma função de limpeza — ou `null` quando ela não
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
  const agressivo = nivel === 'aggressive';
  if (!agressivo && nivel !== 'bold' && nivel !== 'discreet') return null;
  if (jaDispensou()) return null;

  // ── O NÍVEL AGRESSIVO (4.20) — e ele sai ANTES de qualquer `createElement`.
  //
  // Não é economia de estilo. Construir o cartão para descartá-lo faria
  // `foto.src = canal.avatarUrl` numa `<img>` que nunca entra na página — e o
  // navegador BAIXA a imagem assim mesmo. Seria uma requisição de rede por
  // carregamento de página, em todo visitante, para um elemento invisível.
  //
  // A "exibição" do Agressivo é o painel abrindo: uma vez por sessão, e só
  // depois do gatilho composto. `podeAbrirSozinho` é quem marca a sessão, e ele
  // vem ANTES do `aoExibir` de propósito — sessão já usada não é abordagem, e
  // não pode gastar um degrau da escada de familiaridade do 4.19.
  if (agressivo) {
    return armarGatilho(() => {
      if (!podeAbrirSozinho()) return;
      if (aoExibir) aoExibir();
      if (aoAbrir) aoAbrir();
    });
  }

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

  let visivel = false;

  const exibir = () => {
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

  fechar.addEventListener('click', dispensar);
  cartao.addEventListener('click', abrir);

  const desarmar = armarGatilho(exibir);

  return () => {
    desarmar();
    cartao.remove();
  };
};
