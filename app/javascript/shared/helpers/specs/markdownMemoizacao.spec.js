/**
 * ACEITE DO BLOCO 2.12 (§2.2 · W2.15):
 *
 *   «Spy no construtor: 1 chamada para 10 renders.»
 *
 * O espião é no construtor do `markdown-it`, e não numa função nossa, porque é
 * exatamente ele o custo que o bloco elimina: `createMarkdownInstance` monta um
 * MarkdownIt do zero — parser, regras de core/block/inline, renderer — e ainda
 * aplica três plugins. Contar chamadas de `formatMessage` mediria a coisa
 * errada; contar `MarkdownIt(...)` mede o trabalho.
 *
 * `vi.resetModules()` a cada exemplo porque o mapa de instâncias é módulo-nível,
 * e um cache aquecido pelo exemplo anterior faria o segundo caso passar por
 * motivo errado — a contagem tem de partir de zero em cada um.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

// O mock envolve o construtor REAL: o teste mede quantas vezes ele é chamado,
// não substitui o que ele faz. Um dublê que devolvesse objeto vazio mediria a
// contagem com o markdown desligado, e aí o HTML deixaria de provar qualquer
// coisa.
vi.mock('markdown-it', async () => {
  const real = await vi.importActual('markdown-it');
  return { default: vi.fn((...args) => real.default(...args)) };
});

const carregar = async () => {
  const MarkdownIt = (await import('markdown-it')).default;
  const MessageFormatter = (await import('../MessageFormatter')).default;
  MarkdownIt.mockClear();
  return { MarkdownIt, MessageFormatter };
};

beforeEach(() => {
  vi.resetModules();
});

describe('2.12 — uma instância de MarkdownIt por configuração', () => {
  it('dez renders custam UMA construção', async () => {
    const { MarkdownIt, MessageFormatter } = await carregar();

    const saidas = Array.from(
      { length: 10 },
      (_, i) => new MessageFormatter(`Mensagem **${i}**`).formattedMessage
    );

    expect(MarkdownIt).toHaveBeenCalledTimes(1);
    // E o markdown continua sendo markdown — a contagem de 1 não pode vir de
    // o formatador ter parado de formatar.
    expect(saidas[0]).toContain('<strong>0</strong>');
    expect(saidas[9]).toContain('<strong>9</strong>');
  });

  it('`linkify` é o eixo do cache: dois valores, duas instâncias, e só duas', async () => {
    const { MarkdownIt, MessageFormatter } = await carregar();

    const comLink = () =>
      new MessageFormatter('Veja chatwoot.com', false, false, true)
        .formattedMessage;
    const semLink = () =>
      new MessageFormatter('Veja chatwoot.com', false, false, false)
        .formattedMessage;

    Array.from({ length: 5 }).forEach(comLink);
    Array.from({ length: 5 }).forEach(semLink);

    expect(MarkdownIt).toHaveBeenCalledTimes(2);
    // As duas instâncias são de fato diferentes no comportamento — senão o
    // cache estaria devolvendo uma só e o teste de contagem passaria mentindo.
    expect(comLink()).toContain('<a');
    expect(semLink()).not.toContain('<a');
    expect(MarkdownIt).toHaveBeenCalledTimes(2);
  });

  it('`disableImageRendering` não contamina quem compartilha a instância', async () => {
    // Este é o caso que o cache ingênuo quebraria em SILÊNCIO. O método muta o
    // renderer (`renderer.rules.image = () => ''`); com uma instância global,
    // a primeira chamada apagaria imagem de toda superfície do SPA até o
    // próximo reload — e o sintoma apareceria noutra tela, sem nada apontando
    // para a causa.
    const { MessageFormatter } = await carregar();
    // URL ABSOLUTA de propósito: `setImageSizing` faz `new URL(src)` sem base,
    // e um caminho relativo levanta `TypeError: Invalid URL` antes de este
    // teste chegar ao que ele mede. É defeito pré-existente do
    // `imgResizeManager`, roteado no relatório do bloco — não é o que aqui se
    // testa, e usar caminho relativo faria o exemplo falhar por outro motivo.
    const markdown = 'Antes ![alt](https://exemplo.test/imagem.png) depois';

    const semImagem = new MessageFormatter(markdown);
    semImagem.disableImageRendering();
    expect(semImagem.formattedMessage).not.toContain('<img');

    expect(new MessageFormatter(markdown).formattedMessage).toContain('<img');
  });

  it('a instância sem imagem também é reaproveitada', async () => {
    const { MarkdownIt, MessageFormatter } = await carregar();

    Array.from({ length: 10 }).forEach(() => {
      const f = new MessageFormatter('![alt](https://exemplo.test/imagem.png)');
      f.disableImageRendering();
      return f.formattedMessage;
    });

    // Uma para a configuração padrão (criada no primeiro `get md`, se houver) e
    // uma para "sem imagem". Nunca dez.
    expect(MarkdownIt.mock.calls.length).toBeLessThanOrEqual(2);
  });
});
