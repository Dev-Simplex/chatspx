/**
 * Mecanismo de aceite do bloco 2.09 — o breakpoint único.
 *
 * ACEITE (§2.2): "767 px fullscreen, 768 flutuante, **sem ambiguidade**".
 *
 * A ambiguidade não é figura de linguagem, é medida: `sdk.js` traz
 * `min-width: 667px` (flutuante) E `max-width: 667px` (tela cheia) — em
 * exatamente 667 px **as duas** casam, e quem decide é a ordem no arquivo. Some
 * a isso o `max-width: 668px` de `IFrameHelper.js:480`, e em 668 px o CSS trata
 * como desktop enquanto o JS avisa o widget que é celular.
 *
 * A geometria resultante é medida em Chromium (`specs/browser/…`); aqui ficam a
 * varredura que impede a volta dos números antigos e a ponta JS.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MOBILE_BREAKPOINT, isMobileViewport } from '../viewport';

const sdkDir = join(dirname(fileURLToPath(import.meta.url)), '..');

describe('2.09 — um número só decide celular', () => {
  it('o breakpoint é 768', () => {
    expect(MOBILE_BREAKPOINT).toBe(768);
  });

  it('nenhum arquivo do sdk usa mais 667 ou 668 como largura', () => {
    const culpados = readdirSync(sdkDir)
      .filter(nome => nome.endsWith('.js'))
      .filter(nome =>
        /(?:max-width|min-width):\s*66[78]px|\b66[78]\b\s*(?:px)?\s*[),]/.test(
          readFileSync(join(sdkDir, nome), 'utf8')
        )
      );

    expect(culpados).toEqual([]);
  });

  it('as duas faixas do CSS não se sobrepõem em nenhum pixel', () => {
    const { SDK_CSS } = readFileSync(join(sdkDir, 'sdk.js'), 'utf8')
      ? { SDK_CSS: readFileSync(join(sdkDir, 'sdk.js'), 'utf8') }
      : {};

    const maximos = [...SDK_CSS.matchAll(/max-width:\s*(\d+)px/g)].map(m =>
      Number(m[1])
    );
    const minimos = [...SDK_CSS.matchAll(/min-width:\s*(\d+)px/g)].map(m =>
      Number(m[1])
    );

    expect(new Set(maximos)).toEqual(new Set([MOBILE_BREAKPOINT - 1]));
    expect(new Set(minimos)).toEqual(new Set([MOBILE_BREAKPOINT]));
    // Sobreposição seria max >= min; disjunção exige max = min - 1.
    expect(Math.max(...maximos)).toBe(Math.min(...minimos) - 1);
  });

  it('isMobileViewport segue o mesmo número, e 768 já não é celular', () => {
    const emLargura = largura => {
      window.matchMedia = query => ({
        matches:
          largura <= Number(/max-width:\s*(\d+)px/.exec(query)?.[1] ?? -1),
        media: query,
        addEventListener: () => {},
        removeEventListener: () => {},
      });
      return isMobileViewport();
    };

    expect(emLargura(375)).toBe(true);
    expect(emLargura(767)).toBe(true);
    expect(emLargura(768)).toBe(false);
    expect(emLargura(1280)).toBe(false);
  });
});

describe('2.09 — o arquivo continua sendo JavaScript válido', () => {
  // Achado durante este bloco: escrevi um comentário CSS com CRASES dentro da
  // template string `SDK_CSS`, e as duas crases FECHARAM a string no meio. O
  // arquivo deixou de ser JS válido — e nenhum dos dois mecanismos deste bloco
  // percebeu, porque os dois leem `sdk.js` como TEXTO. Quem pegou foi o eslint.
  // Este exemplo importa o módulo de verdade: erro de sintaxe vira vermelho
  // aqui, não só no lint de quem lembrar de rodá-lo.
  it('importa e entrega o CSS como string não vazia', async () => {
    const { SDK_CSS } = await import('../sdk');

    expect(typeof SDK_CSS).toBe('string');
    expect(SDK_CSS.length).toBeGreaterThan(1000);
    expect(SDK_CSS).toContain('.woot-widget-holder');
  });
});

describe('2.09 — a tela cheia respeita a área segura e a altura real', () => {
  const css = () => readFileSync(join(sdkDir, 'sdk.js'), 'utf8');

  it('usa dvh/dvw com fallback — a barra do navegador móvel come 100vh', () => {
    const fullscreen =
      /@media only screen and \(max-width: 767px\) \{([\s\S]*?)\n\}/.exec(
        css()
      )?.[1];

    expect(fullscreen).toBeTruthy();
    expect(fullscreen).toMatch(/height:\s*100%/);
    expect(fullscreen).toMatch(/height:\s*100dvh/);
    expect(fullscreen).toMatch(/width:\s*100%/);
    expect(fullscreen).toMatch(/width:\s*100dvw/);
  });

  it('respeita o recorte do aparelho com env(safe-area-inset-*)', () => {
    expect(css()).toMatch(/env\(safe-area-inset-bottom/);
  });
});
