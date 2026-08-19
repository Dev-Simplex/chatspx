import { readFileSync } from 'node:fs';
import { globSync } from 'node:fs';

/**
 * Régua do bloco 2.01 — vale para os treze primitivos de `widget/ui/`, e para
 * qualquer um que nasça depois: o teste varre o diretório, não uma lista.
 *
 * Os dois aceites de lint do bloco ("nenhum importa de `dashboard/`, nenhum tem
 * cor literal") não são afirmações — são estas asserções. O terceiro,
 * `aria-label` por prop, é o que impede o widget de repetir os 11 controles sem
 * nome acessível que a matriz de snapshot mediu em 18/08.
 */
const PRIMITIVOS = globSync('app/javascript/widget/ui/*.vue').sort();

const ler = arquivo => readFileSync(arquivo, 'utf8');
const semComentarios = fonte =>
  fonte.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

describe('primitivos de widget/ui/', () => {
  it('o diretório tem primitivos para varrer', () => {
    // Guarda contra o falso verde mais fácil deste arquivo: se o glob quebrar,
    // todos os `it.each` abaixo somem e a suíte fica verde sem testar nada —
    // teste que não roda é indistinguível de teste que passa.
    expect(PRIMITIVOS.length).toBeGreaterThan(0);
  });

  describe.each(PRIMITIVOS)('%s', arquivo => {
    it('não importa de dashboard/', () => {
      const imports = [...ler(arquivo).matchAll(/from\s+'([^']+)'/g)].map(
        m => m[1]
      );
      expect(imports.filter(i => i.startsWith('dashboard/'))).toEqual([]);
    });

    it('não importa de shared/components/ui/ (fora do content do widget)', () => {
      // `tailwind.widget.config.js` exclui esse caminho explicitamente
      // (`!./app/javascript/shared/components/ui/**`): importar de lá compila,
      // não avisa, e chega sem estilo no cliente.
      const imports = [...ler(arquivo).matchAll(/from\s+'([^']+)'/g)].map(
        m => m[1]
      );
      expect(
        imports.filter(i => i.startsWith('shared/components/ui/'))
      ).toEqual([]);
    });

    it('não tem cor literal', () => {
      const fonte = semComentarios(ler(arquivo));
      const literais = [
        ...fonte.matchAll(/#[0-9a-fA-F]{3,8}\b/g),
        ...fonte.matchAll(/\brgba?\(\s*\d/g),
        ...fonte.matchAll(/\bhsla?\(\s*\d/g),
      ].map(m => m[0]);
      expect(literais).toEqual([]);
    });

    it('todo aria-label sai de uma prop, nunca de texto fixo', () => {
      const fonte = ler(arquivo);
      // `aria-label="texto"` (sem dois-pontos) é rótulo fixo: não dá para
      // traduzir e não dá para o chamador corrigir.
      const fixos = [...fonte.matchAll(/[^:]aria-label="([^"]*)"/g)].map(
        m => m[1]
      );
      expect(fixos).toEqual([]);
    });
  });
});
