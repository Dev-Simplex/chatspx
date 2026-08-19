/**
 * BLOCO 2.08 — a leitura da preferência, e o que ela decide.
 *
 * O aceite do bloco não é "não animar": é *"entregar o mesmo estado final sem o
 * percurso"*. Quem separa uma coisa da outra é o valor de `behavior`, e é ele
 * que estes exemplos travam — `'auto'` continua rolando até o fim, só que sem
 * percorrer. Um teste que aceitasse "não chamou `scrollTo`" passaria com o
 * botão quebrado para quem tem a preferência ligada.
 *
 * A medição do PERCURSO em si (o navegador de verdade honrando o `behavior`)
 * está em `spec/e2e/widget/movimento.spec.js`. jsdom não rola.
 */
import {
  prefereMenosMovimento,
  comportamentoDeRolagem,
  CONSULTA_MENOS_MOVIMENTO,
} from '../useReducedMotion';

const comMatchMedia = resposta => {
  window.matchMedia = vi.fn().mockImplementation(consulta => ({
    matches: consulta === CONSULTA_MENOS_MOVIMENTO ? resposta : false,
    media: consulta,
  }));
};

describe('2.08 — `prefers-reduced-motion`', () => {
  const original = window.matchMedia;
  afterEach(() => {
    window.matchMedia = original;
  });

  it('sem a preferência, o percurso existe', () => {
    comMatchMedia(false);

    expect(prefereMenosMovimento()).toBe(false);
    expect(comportamentoDeRolagem()).toBe('smooth');
  });

  it('com a preferência, o DESTINO continua o mesmo e só o percurso sai', () => {
    comMatchMedia(true);

    expect(prefereMenosMovimento()).toBe(true);
    // `'auto'` e não `'none'`, `undefined` ou a ausência da chamada: o
    // visitante que pediu menos movimento continua chegando ao fim da lista.
    expect(comportamentoDeRolagem()).toBe('auto');
  });

  it('sem `matchMedia` no ambiente, assume que NÃO há preferência', () => {
    // O widget roda dentro de iframes de host que não controlamos. Responder
    // `true` aqui tiraria o movimento de todo mundo por causa de uma API
    // faltando — que é o erro oposto e mais caro.
    delete window.matchMedia;

    expect(prefereMenosMovimento()).toBe(false);
    expect(comportamentoDeRolagem()).toBe('smooth');
  });

  it('relê a preferência a cada chamada, porque ela muda com o chat aberto', () => {
    comMatchMedia(false);
    expect(comportamentoDeRolagem()).toBe('smooth');

    comMatchMedia(true);
    expect(comportamentoDeRolagem()).toBe('auto');
  });
});
