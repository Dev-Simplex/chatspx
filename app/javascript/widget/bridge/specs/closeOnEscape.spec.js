/**
 * Mecanismo de aceite do bloco 2.11, metade do WIDGET.
 *
 * ACEITE (§2.2): "`Esc` fecha; `document.activeElement` volta ao launcher;
 * nenhum `tabindex` positivo".
 *
 * POR QUE ISTO EXISTE, e a medição que o justifica: `ViewWithHeader.vue` já traz
 * `@keydown.esc="closeWindow"`, mas num `<div>` — e `keydown` só chega lá se o
 * foco estiver DENTRO dele. Com o foco no `<body>` do iframe (o estado logo
 * depois de abrir, antes de o visitante tocar em qualquer coisa), a tecla não
 * encontra o handler e o widget não fecha. O listener precisa ser do documento.
 */
import { registerCloseOnEscape } from '../closeOnEscape';

const enviadas = [];

vi.mock('widget/helpers/utils', () => ({
  IFrameHelper: {
    isIFrame: () => true,
    sendMessage: msg => enviadas.push(msg),
  },
}));

describe('2.11 — Esc fecha o widget', () => {
  let remover;

  beforeEach(() => {
    enviadas.length = 0;
    remover = registerCloseOnEscape();
  });

  afterEach(() => remover?.());

  const teclar = (key, alvo = document) =>
    alvo.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true }));

  it('Escape com o foco no body — o estado logo depois de abrir — fecha', () => {
    teclar('Escape', document.body);

    expect(enviadas).toEqual([{ event: 'closeWindow' }]);
  });

  it('Escape a partir de um campo de texto também fecha', () => {
    const input = document.createElement('input');
    document.body.appendChild(input);
    input.focus();

    teclar('Escape', input);

    expect(enviadas).toEqual([{ event: 'closeWindow' }]);
    input.remove();
  });

  it('outra tecla qualquer não fecha nada', () => {
    teclar('Enter', document.body);
    teclar('a', document.body);
    teclar('Esc', document.body);

    expect(enviadas).toEqual([]);
  });

  it('remover o registro para de escutar — nada de listener órfão', () => {
    remover();
    teclar('Escape', document.body);

    expect(enviadas).toEqual([]);
  });
});

describe('2.11 — a fiação: a mesma porta liga a ponte e o Esc', () => {
  it('registerWidgetListeners faz o Esc funcionar, e o cleanup desliga', async () => {
    // O `beforeEach` que registra o listener vive no describe anterior e não
    // roda aqui — este bloco mede a fiação sozinha.
    enviadas.length = 0;

    const { registerWidgetListeners } = await import('../index');
    const desligar = registerWidgetListeners({});

    document.body.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    expect(enviadas).toEqual([{ event: 'closeWindow' }]);

    desligar();
    enviadas.length = 0;
    document.body.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    expect(enviadas).toEqual([]);
  });
});
