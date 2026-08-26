/**
 * Os 8 aceites da §C.2 do plano 22 — bloco 4.06.
 *
 * jsdom cobre gatilho, cookie e montagem, que é onde os aceites 1–4, 6 e 8
 * vivem. Os que dependem de cascade (alvo de dispensa, `prefers-reduced-motion`
 * e as duas formas) estão em `specs/browser/teaser.check.mjs`, em Chromium real.
 */
import Cookies from 'js-cookie';
import { montarTeaser } from '../teaser';

const CANAL = {
  avatarUrl: 'https://exemplo.test/a.png',
  // Bloco 4.05: o texto do balão passou a ser `teaserText`, resolvido no servidor
  // (`Channel::WebWidget#teaser_text`). `welcomeTagline` aqui viraria fixture morta —
  // presente no objeto, ignorada pelo código, e enganando quem ler depois.
  teaserText: 'Fale com a gente',
  replyTime: 'Responde em minutos',
};

const rolarAte = fracao => {
  Object.defineProperty(document.documentElement, 'scrollHeight', {
    value: 2000,
    configurable: true,
  });
  window.innerHeight = 1000;
  window.scrollY = Math.round((2000 - 1000) * fracao);
  window.dispatchEvent(new Event('scroll'));
};

describe('4.06 — o teaser', () => {
  let holder;
  let abriu;

  beforeEach(() => {
    vi.useFakeTimers();
    document.body.innerHTML = '';
    holder = document.createElement('div');
    document.body.appendChild(holder);
    Cookies.remove('cw_teaser_dismissed');
    abriu = 0;
    window.scrollY = 0;
    // jsdom não implementa; o teaser usa para o quadro de entrada.
    global.requestAnimationFrame = cb => cb();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  const montar = (extra = {}) =>
    montarTeaser({
      holder,
      canal: { ...CANAL, ...(extra.canal || {}) },
      nivel: extra.nivel || 'bold',
      aoAbrir: () => {
        abriu += 1;
      },
      ...extra.opcoes,
    });

  const teaserNoDom = () => holder.querySelector('.woot-teaser');

  // Uma página COM rolagem disponível, em que o visitante não rolou. É este o
  // cenário que o aceite 1 descreve — e não a página curta, tratada no exemplo
  // logo abaixo.
  const paginaRolavel = () => {
    Object.defineProperty(document.documentElement, 'scrollHeight', {
      value: 3000,
      configurable: true,
    });
    window.innerHeight = 1000;
    window.scrollY = 0;
  };

  it('1. oito segundos SOZINHOS não disparam — o gatilho é composto', () => {
    paginaRolavel();
    montar();
    vi.advanceTimersByTime(9000);

    expect(teaserNoDom()).toBeNull();
  });

  it('1d. numa página que NÃO ROLA, o tempo basta — decisão declarada', () => {
    // Landing de uma tela só: exigir 30% de rolagem de uma página que não rola
    // seria exigir o impossível, e o teaser nunca apareceria. A condição de
    // rolagem é considerada satisfeita quando não há o que rolar.
    //
    // Isto é uma DECISÃO, não uma brecha: o aceite 1 protege contra aparecer
    // para quem abriu a aba e foi embora, e nesse caso o sinal de presença é o
    // tempo. Se o produto preferir o oposto — nunca aparecer sem rolagem real —
    // é uma linha em `aoRolar`, e este exemplo vira o seu contrário.
    Object.defineProperty(document.documentElement, 'scrollHeight', {
      value: 600,
      configurable: true,
    });
    window.innerHeight = 1000;

    montar();
    vi.advanceTimersByTime(9000);

    expect(teaserNoDom()).not.toBeNull();
  });

  it('1b. rolagem sozinha também não dispara', () => {
    montar();
    rolarAte(0.5);

    expect(teaserNoDom()).toBeNull();
  });

  it('1c. com as DUAS condições aparece, e aparece uma vez só', () => {
    montar();
    vi.advanceTimersByTime(9000);
    rolarAte(0.5);

    expect(teaserNoDom()).not.toBeNull();

    // Mais rolagem não pode montar um segundo cartão.
    rolarAte(0.9);
    expect(holder.querySelectorAll('.woot-teaser')).toHaveLength(1);
  });

  it('2. dispensado, grava cookie e não volta na próxima montagem', () => {
    montar();
    vi.advanceTimersByTime(9000);
    rolarAte(0.5);
    teaserNoDom().querySelector('.woot-teaser__fechar').click();

    expect(Cookies.get('cw_teaser_dismissed')).toBe('1');

    // Nova página, novo `montarTeaser` — o cookie manda.
    holder.innerHTML = '';
    expect(montar()).toBeNull();
    vi.advanceTimersByTime(9000);
    rolarAte(0.5);
    expect(teaserNoDom()).toBeNull();
  });

  it('3. com banner de cookie visível na página, não dispara', () => {
    const banner = document.createElement('div');
    banner.id = 'cookie-consent';
    banner.getBoundingClientRect = () => ({ width: 600, height: 90 });
    document.body.appendChild(banner);

    montar();
    vi.advanceTimersByTime(9000);
    rolarAte(0.5);

    expect(teaserNoDom()).toBeNull();
  });

  it('4. o painel NÃO abre sozinho em nenhum caminho', () => {
    montar();
    vi.advanceTimersByTime(9000);
    rolarAte(0.5);

    // Exibir é exibir. Abrir só acontece por clique do visitante.
    expect(abriu).toBe(0);

    teaserNoDom().click();
    expect(abriu).toBe(1);
  });

  it('6. tem role="status" e NÃO recebe foco', () => {
    montar();
    vi.advanceTimersByTime(9000);
    rolarAte(0.5);
    const cartao = teaserNoDom();

    expect(cartao.getAttribute('role')).toBe('status');
    // Nada de `tabindex` no cartão: o foco do visitante não pode ser roubado
    // por algo que apareceu sozinho.
    expect(cartao.hasAttribute('tabindex')).toBe(false);
    expect(document.activeElement).not.toBe(cartao);
  });

  it('8. com teaserEnabled: false o código NÃO é montado', () => {
    const desmontar = montar({ canal: { teaserEnabled: false } });

    // Não devolve nem função de limpeza: não há nada para limpar porque nada
    // foi criado — nem DOM, nem timer, nem listener de scroll.
    expect(desmontar).toBeNull();
    vi.advanceTimersByTime(9000);
    rolarAte(0.5);
    expect(teaserNoDom()).toBeNull();
  });

  it('10. Discreto e Chamativo são o MESMO DOM, com classe diferente', () => {
    montar({ nivel: 'bold' });
    vi.advanceTimersByTime(9000);
    rolarAte(0.5);
    const chamativo = teaserNoDom();
    const marcaChamativo = chamativo.outerHTML.replace(
      'woot-teaser--bold',
      'NIVEL'
    );

    holder.innerHTML = '';
    Cookies.remove('cw_teaser_dismissed');
    vi.useFakeTimers();
    montar({ nivel: 'discreet' });
    vi.advanceTimersByTime(9000);
    rolarAte(0.5);
    const discreto = teaserNoDom();

    expect(discreto.classList.contains('woot-teaser--discreet')).toBe(true);
    // O DOM é idêntico fora a classe de nível: a foto e o chip continuam lá,
    // e é o CSS que os esconde. Um segundo componente dobraria o peso do
    // arquivo que 100% dos visitantes baixam.
    expect(discreto.querySelector('.woot-teaser__foto')).not.toBeNull();
    expect(discreto.querySelector('.woot-teaser__chip')).not.toBeNull();
    expect(discreto.outerHTML.replace('woot-teaser--discreet', 'NIVEL')).toBe(
      marcaChamativo
    );
  });
});
