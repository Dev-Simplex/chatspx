/**
 * Mecanismo de aceite do bloco 2.11 — a LIGAÇÃO, no host.
 *
 * Os módulos `inertBackground` e `closeOnEscape` têm testes próprios de
 * comportamento. Este arquivo prova a outra metade, que é onde recurso costuma
 * morrer: que o toggle do lançador de fato os aciona. Peça certa que ninguém
 * chama é indistinguível de peça ausente.
 *
 * Também trava as duas asserções que o aceite pede e que já estavam certas na
 * base — `document.activeElement` no lançador e nenhum `tabindex` positivo. O
 * bloco VERIFICA o que existe em vez de reimplementar: `chatBubble.focus()` já
 * estava em `handleBubbleToggle`, e reescrever teria duplicado a lógica.
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const raizJs = join(dirname(fileURLToPath(import.meta.url)), '../..');

// `handleBubbleToggle` avisa o iframe, e no jsdom não existe iframe: sem este
// dublê o teste morreria em `contentWindow` antes de chegar ao que ele mede.
vi.mock('../IFrameHelper', () => ({
  IFrameHelper: { events: { onBubbleToggle: vi.fn() } },
}));

const larguraDaTela = largura => {
  window.matchMedia = query => ({
    matches: (() => {
      const limite = Number(/max-width:\s*(\d+)px/.exec(query)?.[1] ?? 0);
      return largura <= limite;
    })(),
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {},
  });
};

const montarPagina = () => {
  document.body.innerHTML = '';
  const conteudo = document.createElement('main');
  document.body.appendChild(conteudo);
  return conteudo;
};

describe('2.11 — o toggle aciona as peças de acessibilidade', () => {
  let bubbleHelpers;
  let conteudo;

  beforeEach(async () => {
    vi.resetModules();
    conteudo = montarPagina();
    window.$chatwoot = { isOpen: false, hideMessageBubble: false };
    bubbleHelpers = await import('../bubbleHelpers');
    document.body.appendChild(bubbleHelpers.chatBubble);
    document.body.appendChild(bubbleHelpers.closeBubble);
  });

  it('em celular, abrir torna o resto da página inerte', () => {
    larguraDaTela(375);

    bubbleHelpers.onBubbleClick({ toggleValue: true });

    expect(conteudo.hasAttribute('inert')).toBe(true);
  });

  it('em desktop, abrir NÃO congela a página — o widget é flutuante ali', () => {
    larguraDaTela(1280);

    bubbleHelpers.onBubbleClick({ toggleValue: true });

    expect(conteudo.hasAttribute('inert')).toBe(false);
  });

  it('fechar devolve a página e o foco ao lançador', () => {
    larguraDaTela(375);
    bubbleHelpers.onBubbleClick({ toggleValue: true });

    bubbleHelpers.onBubbleClick({ toggleValue: false });

    expect(conteudo.hasAttribute('inert')).toBe(false);
    expect(document.activeElement).toBe(bubbleHelpers.chatBubble);
  });

  it('fechar em desktop também devolve o foco — a regra não é só do celular', () => {
    larguraDaTela(1280);
    bubbleHelpers.onBubbleClick({ toggleValue: true });

    bubbleHelpers.onBubbleClick({ toggleValue: false });

    expect(document.activeElement).toBe(bubbleHelpers.chatBubble);
  });
});

describe('2.11 — nenhum tabindex positivo', () => {
  // `tabindex` positivo tira o elemento da ordem natural do documento e joga a
  // ordem de foco da PÁGINA INTEIRA para dentro do widget. É proibido pelo
  // aceite, e a varredura é o que impede a volta silenciosa.
  const arquivos = (dir, acc = []) => {
    readdirSync(dir).forEach(nome => {
      const caminho = join(dir, nome);
      if (statSync(caminho).isDirectory()) {
        if (!['node_modules', 'specs'].includes(nome)) arquivos(caminho, acc);
      } else if (/\.(vue|js)$/.test(nome)) {
        acc.push(caminho);
      }
    });
    return acc;
  };

  it.each(['widget', 'sdk', 'shared'])(
    '%s não usa tabindex positivo',
    pasta => {
      const culpados = arquivos(join(raizJs, pasta)).filter(caminho =>
        /tabindex\s*[=:]\s*["']?[1-9]/i.test(readFileSync(caminho, 'utf8'))
      );

      expect(culpados).toEqual([]);
    }
  );
});
