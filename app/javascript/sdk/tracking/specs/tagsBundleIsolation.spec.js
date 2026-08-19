import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { PII_KEYS } from '../tags';

/**
 * As duas guardas de JUNCAO do bloco 5.10. Nenhuma das duas testa comportamento: as duas
 * testam que dois arquivos que nao se enxergam continuam concordando. E o tipo de defeito que
 * fica verde dos dois lados e quebrado no meio.
 */

const TAGS = 'app/javascript/sdk/tracking/tags.js';
const MODELO_RUBY = 'app/models/tracking_event.rb';

describe('5.10 — a ponte nao pode importar o consentimento (dois bundles, dois estados)', () => {
  /**
   * `entrypoints/sdk.js` importa `sdk/tracking/consent.js`, e o build de `vite.lib.config.ts`
   * o INLINA no `sdk.js` (`inlineDynamicImports: true`). `tags.js` mora no artefato
   * `tracking.js`, construido por `vite.tracking.config.ts` — outro bundle.
   *
   * Um `import ... from './consent'` aqui produziria DUAS instancias do modulo, cada uma com
   * o seu objeto `state`. `$chatwoot.setConsent({ ad_storage: 'granted' })` atualizaria a do
   * `sdk.js`; a ponte leria a do `tracking.js`, que nunca sai de "negado". O teste unitario de
   * cada lado ficaria verde e o gate estaria morto no site do cliente.
   *
   * Por isso `isAllowed` e parametro. Este exemplo e o que impede alguem de "simplificar"
   * trocando o parametro por um import.
   */
  it('tags.js nao importa nada de ./consent', () => {
    const fonte = readFileSync(TAGS, 'utf8');
    const imports = [
      ...fonte.matchAll(/^import[\s\S]*?from\s+'([^']+)';/gm),
    ].map(m => m[1]);

    expect(imports).not.toContain('./consent');
    expect(imports.filter(caminho => caminho.includes('consent'))).toEqual([]);
  });

  it('e o gate continua sendo parametro de createTagsBridge', () => {
    expect(readFileSync(TAGS, 'utf8')).toContain('isAllowed = () => true');
  });
});

describe('5.10 — a lista de PII do navegador e a do servidor sao a MESMA', () => {
  /**
   * O servidor recusa PII crua em `properties` (`TrackingEvent::PII_KEYS`). A ponte descarta as
   * mesmas chaves antes de publicar no `dataLayer` e nos params do `fbq`/`gtag`, porque o
   * `window` do cliente e legivel por qualquer script de terceiro da pagina (regra RC5/R10).
   *
   * Duas listas em duas linguagens sao duas listas que divergem. Este exemplo le a do RUBY e
   * exige que batam: acrescentar uma chave de um lado so reprova o CI nomeando a chave.
   */
  it('bate com TrackingEvent::PII_KEYS', () => {
    const ruby = readFileSync(MODELO_RUBY, 'utf8');
    const declaracao = ruby.match(/PII_KEYS\s*=\s*%w\[([^\]]+)\]/);

    expect(declaracao).toBeTruthy();
    const doServidor = declaracao[1].trim().split(/\s+/);

    expect([...PII_KEYS].sort()).toEqual([...doServidor].sort());
  });
});
