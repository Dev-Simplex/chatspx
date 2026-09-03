/*
 * Plugin de diagnóstico do build — responde "o que ENTROU neste chunk?".
 *
 * Existe porque procurar o nome de uma dependência dentro do arquivo gerado
 * MENTE: `grep amplitude` acha atributo de SVG, string de licença e
 * comentário; e o RÓTULO do chunk (`utils.esm-*.js`, `Validators-*.js`) é só
 * o nome do módulo que o Rollup elegeu como representante — não prova o
 * conteúdo. A única fonte confiável é `chunk.modules` do Rollup, que traz o
 * fecho real de módulos por chunk com o tamanho renderizado de cada um.
 *
 * Ligado só sob demanda, para não custar nada no build normal:
 *
 *   VITE_CHUNK_STATS=tmp/stats-widget.json bin/vite build
 */
import fs from 'node:fs';
import path from 'node:path';
import type { Plugin } from 'vite';

export function chunkStats(): Plugin | null {
  const out = process.env.VITE_CHUNK_STATS;
  if (!out) return null;

  return {
    name: 'spx-chunk-stats',
    apply: 'build',
    generateBundle(_options, bundle) {
      const chunks = Object.values(bundle)
        .filter((c: any) => c.type === 'chunk')
        .map((c: any) => ({
          fileName: c.fileName,
          name: c.name,
          isEntry: c.isEntry,
          isDynamicEntry: c.isDynamicEntry,
          imports: c.imports,
          dynamicImports: c.dynamicImports,
          modules: Object.entries(c.modules).map(([id, m]: [string, any]) => ({
            id,
            renderedLength: m.renderedLength,
            originalLength: m.originalLength,
          })),
        }));
      // Grafo de modulos: `importedIds` (estatico) x `dynamicallyImportedIds`.
      // E o que permite responder POR QUE um pacote entrou no first-paint —
      // a cadeia de imports desde a entrada, e nao um palpite pelo rotulo.
      const graph: Record<string, any> = {};
      for (const id of this.getModuleIds()) {
        const info = this.getModuleInfo(id);
        if (!info) continue;
        graph[id] = {
          importedIds: info.importedIds,
          dynamicallyImportedIds: info.dynamicallyImportedIds,
        };
      }

      const file = path.resolve(out);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, JSON.stringify({ chunks, graph }, null, 1));
      // eslint-disable-next-line no-console
      console.log(`[spx-chunk-stats] ${chunks.length} chunks → ${file}`);
    },
  };
}
