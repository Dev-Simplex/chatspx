// @vitest-environment node
//
// Ambiente `node` e não `jsdom`: o plugin chama o esbuild, e o esbuild recusa
// rodar sob o `TextEncoder` do jsdom («new TextEncoder().encode("") instanceof
// Uint8Array» é falso lá). É o mesmo esbuild que o build de produção usa.
/*
 * ONDE ESTE ARQUIVO MORA, E POR QUÊ NÃO EM `entrypoints/specs/`.
 *
 * O `vite_ruby` varre `app/javascript/entrypoints/` RECURSIVAMENTE e trata
 * todo arquivo lá dentro como entrypoint do build. Um spec ali vira entrada,
 * e como este importa `vite.sdk-css.ts` (que importa `vite`), o Rollup passou
 * a puxar o próprio Rollup para o bundle da aplicação e o build morreu em
 * «failed to resolve import "fsevents"». Spec de configuração de build fica
 * fora de `entrypoints/`.
 */

/**
 * `vite.sdk-css.ts` — a minificação do CSS embutido no `sdk.js` (bloco 2.18).
 *
 * O `sdk.js` tem DOIS tetos (A13) e é o CRU que aperta. 9.983 dos 45.229 B do
 * arquivo eram uma template string com CSS indentado: template string é dado,
 * e nenhum minificador de JS a toca.
 *
 * O que estes testes protegem não é a economia — é a GUARDA. Se o literal for
 * renomeado, movido ou ganhar interpolação, o plugin tem de ABORTAR o build.
 * Um plugin que não encontra o alvo e segue em silêncio devolve os bytes sem
 * ninguém perceber, e o teto cru volta a estourar por um motivo invisível.
 */
import { describe, it, expect } from 'vitest';
import { sdkCssMinify } from '../../../../vite.sdk-css';

const ID = '/repo/app/javascript/sdk/sdk.js';

const rodar = (codigo, id = ID) => {
  const plugin = sdkCssMinify();
  const ctx = {
    error(msg) {
      throw new Error(typeof msg === 'string' ? msg : msg.message);
    },
  };
  return plugin.transform.call(ctx, codigo, id);
};

describe('sdkCssMinify', () => {
  it('minifica o CSS do literal e preserva a declaração', async () => {
    const fonte = [
      "import x from 'y';",
      'export const SDK_CSS = `',
      '.woot-widget-holder {',
      '  opacity: 1;',
      '  z-index: 2147483000 !important;',
      '}',
      '`;',
      'export const outro = 1;',
    ].join('\n');

    const { code } = await rodar(fonte);

    expect(code).toContain('export const SDK_CSS = `');
    expect(code).toContain('.woot-widget-holder{');
    // A economia é o ponto do bloco: o literal tem de encolher de verdade.
    expect(code.length).toBeLessThan(fonte.length);
    // E o resto do módulo tem de sair intacto.
    expect(code).toContain("import x from 'y';");
    expect(code).toContain('export const outro = 1;');
  });

  it('não toca em módulo que não seja o `sdk/sdk.js`', async () => {
    const fonte = 'export const SDK_CSS = `\n.a { color: red; }\n`;';
    expect(await rodar(fonte, '/repo/app/javascript/widget/App.vue')).toBeNull();
  });

  it('ABORTA quando o literal `SDK_CSS` não existe mais', async () => {
    // O caso real: alguém renomeia a constante ou move o CSS de arquivo.
    const fonte = 'export const CSS_DO_SDK = `\n.a { color: red; }\n`;';
    await expect(rodar(fonte)).rejects.toThrow(/não encontrei/);
  });

  it('ABORTA quando o literal ganha interpolação', async () => {
    // Minificar um literal com `${}` apagaria a expressão: melhor não gerar.
    const fonte =
      'export const SDK_CSS = `\n.a { color: ${cor}; }\n`;';
    await expect(rodar(fonte)).rejects.toThrow(/interpolação/);
  });
});
