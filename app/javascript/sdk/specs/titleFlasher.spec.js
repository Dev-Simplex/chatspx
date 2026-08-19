import { createTitleFlasher } from '../titleFlasher';

/**
 * Bloco 4.11 (W4.6): 650 ms de intervalo, 60 s de duracao, so com a aba
 * oculta, para no `visibilitychange`, nao reentra.
 *
 * Os numeros sao do plano e nao se afrouxam: um titulo que pisca a cada 2 s
 * nao chama atencao, e um que pisca para sempre faz a pessoa fechar a aba.
 */
const criarDoc = ({ hidden = true, title = 'Loja da Simplex' } = {}) => {
  const ouvintes = {};
  return {
    hidden,
    title,
    addEventListener: (evento, fn) => {
      ouvintes[evento] = fn;
    },
    removeEventListener: evento => {
      delete ouvintes[evento];
    },
    disparar: evento => ouvintes[evento]?.(),
    temOuvinte: evento => Boolean(ouvintes[evento]),
  };
};

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe('o piscar do título', () => {
  it('alterna a cada 650 ms entre o alerta e o título original', () => {
    const doc = criarDoc();
    const flasher = createTitleFlasher({ doc });

    expect(flasher.start('Nova mensagem')).toBe(true);
    expect(doc.title).toBe('Loja da Simplex');

    vi.advanceTimersByTime(650);
    expect(doc.title).toBe('Nova mensagem');

    vi.advanceTimersByTime(650);
    expect(doc.title).toBe('Loja da Simplex');

    vi.advanceTimersByTime(650);
    expect(doc.title).toBe('Nova mensagem');
  });

  it('para sozinho em 60 s e devolve o título original', () => {
    const doc = criarDoc();
    const flasher = createTitleFlasher({ doc });
    flasher.start('Nova mensagem');

    vi.advanceTimersByTime(59_000);
    expect(flasher.isRunning()).toBe(true);

    vi.advanceTimersByTime(1_000);

    expect(flasher.isRunning()).toBe(false);
    expect(doc.title).toBe('Loja da Simplex');
  });

  it('NÃO pisca com a aba visível — quem está olhando não precisa de alerta', () => {
    const doc = criarDoc({ hidden: false });
    const flasher = createTitleFlasher({ doc });

    expect(flasher.start('Nova mensagem')).toBe(false);
    expect(flasher.isRunning()).toBe(false);

    vi.advanceTimersByTime(5_000);
    expect(doc.title).toBe('Loja da Simplex');
  });

  it('para no visibilitychange, no instante em que a pessoa volta', () => {
    const doc = criarDoc();
    const flasher = createTitleFlasher({ doc });
    flasher.attach();
    flasher.start('Nova mensagem');
    vi.advanceTimersByTime(650);
    expect(doc.title).toBe('Nova mensagem');

    doc.hidden = false;
    doc.disparar('visibilitychange');

    expect(flasher.isRunning()).toBe(false);
    expect(doc.title).toBe('Loja da Simplex');
  });

  it('NÃO reentra: segunda mensagem não cria um segundo ciclo', () => {
    const doc = criarDoc();
    const flasher = createTitleFlasher({ doc });

    expect(flasher.start('Nova mensagem')).toBe(true);
    vi.advanceTimersByTime(650);
    // enquanto pisca, o titulo corrente e o alerta — se o start reentrasse,
    // ele guardaria "Nova mensagem" como original e nunca mais devolveria
    expect(flasher.start('Nova mensagem')).toBe(false);

    flasher.stop();
    expect(doc.title).toBe('Loja da Simplex');
  });

  it('parar sem ter começado não quebra nem mexe no título', () => {
    const doc = criarDoc();
    const flasher = createTitleFlasher({ doc });

    flasher.stop();

    expect(doc.title).toBe('Loja da Simplex');
  });

  it('sem texto de alerta não pisca — título vazio na aba é pior que nada', () => {
    const doc = criarDoc();
    const flasher = createTitleFlasher({ doc });

    expect(flasher.start('')).toBe(false);
    expect(flasher.start(undefined)).toBe(false);
  });
});
