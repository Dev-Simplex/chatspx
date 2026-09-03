/**
 * Guarda de paridade entre os DOIS documentos que montam o widget.
 *
 * O widget é montado em `#app`, e esse elemento existe escrito em dois lugares:
 *
 *   · `app/views/widgets/show.html.erb`            — o documento de PRODUÇÃO
 *   · `spec/e2e/widget/harness/widget-server.mjs`  — o documento do HARNESS e2e
 *
 * Duas cópias do mesmo contrato é a forma de defeito que esta onda mais pagou
 * caro. E não é hipótese: acrescentar `.woot-widget-app` só no ERB fez a matriz
 * do widget falhar na corrida seguinte, porque o harness continuava servindo o
 * `<div>` antigo — o `color-scheme` do bloco 2.10 não tinha onde se prender e o
 * tema escuro do painel sumiu, sem que nenhum teste dissesse por quê.
 *
 * Este arquivo faz a divergência falhar NOMEANDO o arquivo esquecido, em vez de
 * aparecer sete minutos depois como um snapshot estranho.
 */
import fs from 'fs';
import path from 'path';

// Este arquivo vive em `app/javascript/widget/specs/` e não ao lado do harness
// porque o vitest só varre `app/**` (ver `include` em `vitest.config.ts`) — uma
// guarda que o runner não enxerga não guarda nada.
const RAIZ = path.resolve(__dirname, '..', '..', '..', '..');
const ERB = path.join(RAIZ, 'app/views/widgets/show.html.erb');
const HARNESS = path.join(RAIZ, 'spec/e2e/widget/harness/widget-server.mjs');

// Extrai o conjunto de classes do elemento de montagem, sem depender de ordem
// nem de aspas: o que importa é QUAIS classes existem.
const classesDoPontoDeMontagem = arquivo => {
  const conteudo = fs.readFileSync(arquivo, 'utf-8');
  const achado = conteudo.match(/<div\s+id="app"\s+class="([^"]*)"/);
  if (!achado) {
    throw new Error(`não achei <div id="app" class="…"> em ${arquivo}`);
  }
  return achado[1].split(/\s+/).filter(Boolean).sort();
};

describe('paridade do ponto de montagem do widget', () => {
  it('o ERB de produção e o harness e2e montam com as MESMAS classes', () => {
    expect(classesDoPontoDeMontagem(HARNESS)).toEqual(
      classesDoPontoDeMontagem(ERB)
    );
  });

  it('o gancho de `color-scheme` do bloco 2.10 está nos dois', () => {
    // Asserção por VALOR e não só de igualdade: se alguém remover a classe dos
    // DOIS arquivos, o teste acima continuaria verde e o tema escuro do painel
    // sumiria em silêncio.
    expect(classesDoPontoDeMontagem(ERB)).toContain('woot-widget-app');
    expect(classesDoPontoDeMontagem(HARNESS)).toContain('woot-widget-app');
  });
});
