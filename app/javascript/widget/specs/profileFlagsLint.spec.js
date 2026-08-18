/**
 * MECANISMO DE ACEITE DO BLOCO 3.05.
 *
 * O aceite do PLANO-MESTRE §2.2 é literalmente um grep:
 *
 *   grep -rn "widgetProfile" app/javascript/widget/  →  não casa em nenhum `v-if` de template
 *
 * A regra que ele protege (22-plano-widget §B.3 / arbitragem A3): **o widget lê flags planas,
 * nunca o nome do perfil**. `widgetProfile` existe só para telemetria e para o rótulo na tela
 * de configuração do dashboard.
 *
 * Um grep de linha de comando não roda em CI e não falha build. Este spec É o grep, com dente.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const WIDGET_ROOT = join(process.cwd(), 'app/javascript/widget');

/** Único lugar onde `widgetProfile` pode ser citado: o resolvedor e seus consumidores diretos. */
const ALLOWED_FILES = [
  'helpers/profileConfigHelper.js',
  'helpers/specs/profileConfigHelper.spec.js',
  'mixins/configMixin.js',
  'mixins/specs/configMixin.profileFlags.spec.js',
  'store/modules/appConfig.js',
  'specs/profileFlagsLint.spec.js',
];

const walk = dir =>
  readdirSync(dir)
    .filter(entry => entry !== 'node_modules')
    .flatMap(entry => {
      const full = join(dir, entry);
      if (statSync(full).isDirectory()) return walk(full);
      return /\.(vue|js|ts)$/.test(entry) ? [full] : [];
    });

/** Extrai o bloco <template> de um SFC. Arquivo não-Vue devolve string vazia. */
const templateOf = source => {
  const match = source.match(/<template[^>]*>([\s\S]*)<\/template>/);
  return match ? match[1] : '';
};

/**
 * Casa qualquer diretiva de renderização condicional que cite `widgetProfile`:
 * `v-if`, `v-else-if`, `v-show`, e as formas com `:` de binding.
 */
const CONDITIONAL_DIRECTIVE =
  /\b(v-if|v-else-if|v-show)\s*=\s*(["'])([\s\S]*?)\2/g;

const files = walk(WIDGET_ROOT);

describe('3.05 — o widget lê flags planas, nunca o nome do perfil', () => {
  it('varreu a árvore inteira do widget (a guarda contra o teste que não testa nada)', () => {
    expect(files.length).toBeGreaterThan(100);
    expect(files.some(f => f.endsWith('mixins/configMixin.js'))).toBe(true);
  });

  it('nenhum v-if / v-else-if / v-show de template cita widgetProfile', () => {
    const offenders = files
      .map(file => ({ file, source: readFileSync(file, 'utf8') }))
      .filter(({ source }) => source.includes('widgetProfile'))
      .flatMap(({ file, source }) =>
        [...templateOf(source).matchAll(CONDITIONAL_DIRECTIVE)]
          .filter(match => match[3].includes('widgetProfile'))
          .map(match => `${relative(process.cwd(), file)} → ${match[0]}`)
      );

    expect(offenders).toEqual([]);
  });

  it('widgetProfile só é citado no resolvedor e nos seus dois consumidores', () => {
    const citing = files
      .filter(f => readFileSync(f, 'utf8').includes('widgetProfile'))
      .map(f => relative(WIDGET_ROOT, f))
      .sort();

    expect(citing.filter(f => !ALLOWED_FILES.includes(f))).toEqual([]);
  });

  it('as 11 flags planas são consumíveis pelo mixin E pelo store — as duas pontas', async () => {
    const mixinSource = readFileSync(
      join(WIDGET_ROOT, 'mixins/configMixin.js'),
      'utf8'
    );
    const storeSource = readFileSync(
      join(WIDGET_ROOT, 'store/modules/appConfig.js'),
      'utf8'
    );

    // As duas pontas importam o MESMO resolvedor. É o que impede a classe de defeito
    // produtor/consumidor que custou caro na Onda 0 (upstream filtrava na leitura,
    // formulário reenviava inteiro, controller sobrescrevia).
    expect(mixinSource).toContain('profileConfigHelper');
    expect(storeSource).toContain('profileConfigHelper');

    const { PROFILE_CONFIG_DEFAULTS } = await import(
      '../helpers/profileConfigHelper'
    );
    expect(Object.keys(PROFILE_CONFIG_DEFAULTS)).toHaveLength(11);
  });
});
