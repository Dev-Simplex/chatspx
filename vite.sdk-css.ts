/*
 * Minificação do `SDK_CSS` — bloco 2.18, frente do `sdk.js`.
 *
 * `app/javascript/sdk/sdk.js` exporta o CSS do lançador como TEMPLATE STRING.
 * Template string é DADO, não código: nenhum minificador de JS a toca, então
 * as 409 linhas de CSS indentado do fonte viajam inteiras, com indentação e
 * quebras, dentro do único arquivo que 100% dos visitantes de todos os sites
 * de todos os clientes baixam (A13). São 9.983 B crus dos 45.229 do arquivo.
 *
 * Aqui o CSS é minificado em tempo de build — mesma semântica, 1.622 B a
 * menos crus. É o esbuild que já está no processo, com `loader: 'css'`.
 *
 * A GUARDA É O PONTO. Se alguém renomear o `SDK_CSS`, movê-lo de arquivo ou
 * introduzir interpolação (`${}`) dentro dele, este plugin ABORTA o build.
 * A alternativa — não achar e seguir em silêncio — devolveria os 1.622 B sem
 * ninguém notar, e o teto cru do gate voltaria a estourar por um motivo que
 * não aparece em lugar nenhum.
 */
import path from 'node:path';
import { transformWithEsbuild } from 'vite';
import type { Plugin } from 'vite';

const ALVO = path.join('app', 'javascript', 'sdk', 'sdk.js');
const LITERAL = /(export const SDK_CSS = )`([\s\S]*?)`;/;

export function sdkCssMinify(): Plugin {
  return {
    name: 'spx-sdk-css-minify',
    apply: 'build',
    enforce: 'pre',
    async transform(code, id) {
      if (!id.split('?')[0].endsWith(ALVO)) return null;

      const achado = code.match(LITERAL);
      if (!achado) {
        this.error(
          `spx-sdk-css-minify: não encontrei \`export const SDK_CSS = \`...\`\` em ${ALVO}. ` +
            `O CSS do lançador voltaria ao bundle sem minificar e o teto cru do ` +
            `sdk.js (40.000 B) estouraria em silêncio. Ajuste o plugin ou o fonte.`
        );
        return null;
      }

      const cru = achado[2];
      if (cru.includes('${')) {
        this.error(
          'spx-sdk-css-minify: `SDK_CSS` passou a ter interpolação `${}`. ' +
            'Minificar o literal apagaria a expressão — abortando em vez de gerar CSS errado.'
        );
        return null;
      }

      const { code: min } = await transformWithEsbuild(cru, 'sdk-css.css', {
        loader: 'css',
        minify: true,
      });

      // O minificador de CSS não produz crase nem `${`, mas escapar é barato e
      // é o que impede um caractere novo de virar sintaxe de template.
      const seguro = min
        .replace(/\\/g, '\\\\')
        .replace(/`/g, '\\`')
        .replace(/\$\{/g, '\\${')
        .trim();

      return {
        code: code.replace(LITERAL, (_m, decl) => `${decl}\`${seguro}\`;`),
        map: null,
      };
    },
  };
}
