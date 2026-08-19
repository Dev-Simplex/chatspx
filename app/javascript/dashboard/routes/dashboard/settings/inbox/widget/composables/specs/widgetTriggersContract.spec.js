import fs from 'fs';
import path from 'path';
import { DEFAULT_TRIGGERS } from '../widgetConfigFields';
import {
  APPROACHES,
  DEFAULT_APPROACH,
  DEFAULT_DEGRADE_ON_RETURN,
  DEVICES,
  MOBILE_APPROACHES,
  TRIGGER_IDS,
  TRIGGER_LIMITS,
  URL_OPERATORS,
  resolveMobileApproach,
} from '../widgetTriggersContract';

/**
 * A tela e o servidor tem de concordar sobre os gatilhos, e o unico jeito de
 * isso nao se separar em silencio e LER o arquivo Ruby.
 *
 * Aqui o custo da divergencia e maior que na aparencia: o schema tem
 * `additionalProperties: false` em todos os niveis, entao uma chave a mais nao
 * e ignorada — ela derruba o PATCH INTEIRO com 422. A tela diria "salvo" e o
 * banco nao mudaria.
 */
const rubyPath = path.resolve(
  process.cwd(),
  'app/models/concerns/widget_triggers_schema.rb'
);
const resolvablePath = path.resolve(
  process.cwd(),
  'app/models/concerns/widget_config_resolvable.rb'
);
const schemaRuby = fs.readFileSync(rubyPath, 'utf8');
const resolvableRuby = fs.readFileSync(resolvablePath, 'utf8');

const listaRuby = nome =>
  new RegExp(`${nome}\\s*=\\s*%w\\[([^\\]]+)\\]`)
    .exec(schemaRuby)?.[1]
    .trim()
    .split(/\s+/);

/** Aceita `86_400` e `86400`. */
const numeroRuby = expressao => {
  const bruto = new RegExp(expressao).exec(schemaRuby)?.[1];
  return bruto === undefined ? undefined : Number(bruto.replace(/_/g, ''));
};

describe('a tela e o servidor concordam sobre os gatilhos', () => {
  it('os dois arquivos Ruby foram mesmo lidos', () => {
    expect(schemaRuby).toContain('module WidgetTriggersSchema');
    expect(resolvableRuby).toContain('def resolved_widget_approach');
  });

  it('os sete gatilhos são os mesmos, e na mesma quantidade', () => {
    expect([...TRIGGER_IDS].sort()).toEqual(
      [...listaRuby('TRIGGER_IDS')].sort()
    );
    expect(TRIGGER_IDS).toHaveLength(7);
  });

  it('os três níveis de abordagem são os mesmos', () => {
    expect(APPROACHES).toEqual(listaRuby('APPROACHES'));
    expect(MOBILE_APPROACHES).toEqual(listaRuby('MOBILE_APPROACHES'));
    // e o celular NUNCA oferece o nível que abre o painel sozinho
    expect(MOBILE_APPROACHES).not.toContain('aggressive');
  });

  it('os defaults da abordagem são os do servidor', () => {
    expect(DEFAULT_APPROACH).toBe(
      /DEFAULT_APPROACH = '([a-z]+)'/.exec(schemaRuby)[1]
    );
    expect(DEFAULT_DEGRADE_ON_RETURN).toBe(
      /DEFAULT_DEGRADE_ON_RETURN = (true|false)/.exec(schemaRuby)[1] === 'true'
    );
  });

  it('os operadores de URL e os dispositivos são os mesmos', () => {
    expect(URL_OPERATORS).toEqual(listaRuby('URL_OPERATORS'));
    expect(DEVICES).toEqual(listaRuby('DEVICES'));
  });

  it('os tetos que a tela mostra são os que o servidor recusa', () => {
    expect(TRIGGER_LIMITS.valueMax).toBe(
      numeroRuby(
        "'value' => \\{ 'type' => 'integer', 'minimum' => 0, 'maximum' => ([\\d_]+) \\}"
      )
    );
    expect(TRIGGER_LIMITS.selectorMaxLength).toBe(
      numeroRuby("'selector' => \\{[^}]*'maxLength' => ([\\d_]+)")
    );
    expect(TRIGGER_LIMITS.cooldownMax).toBe(
      numeroRuby(
        "'cooldown_seconds' => \\{ 'type' => 'integer', 'minimum' => 0, 'maximum' => ([\\d_]+) \\}"
      )
    );
    expect(TRIGGER_LIMITS.maxPerSessionMax).toBe(
      numeroRuby(
        "'max_per_session' => \\{ 'type' => 'integer', 'minimum' => 0, 'maximum' => ([\\d_]+) \\}"
      )
    );
    expect(TRIGGER_LIMITS.maxTriggers).toBe(
      numeroRuby("'triggers' => \\{ 'type' => 'array', 'maxItems' => ([\\d_]+)")
    );
  });

  it('a tela resolve a abordagem do celular como o servidor resolve', () => {
    // herda o desktop quando não há valor próprio
    expect(resolveMobileApproach(null, 'discreet')).toBe('discreet');
    expect(resolveMobileApproach('', 'bold')).toBe('bold');
    // e NUNCA herda `aggressive`: cai para o default
    expect(resolveMobileApproach(null, 'aggressive')).toBe('bold');
    expect(resolveMobileApproach('aggressive', 'aggressive')).toBe('bold');
    // sem nada gravado, o default
    expect(resolveMobileApproach(null, null)).toBe('bold');
  });

  it('o rascunho da tela não carrega chave que o schema não conhece', () => {
    // `additionalProperties: false`: chave a mais não é ignorada — derruba o
    // PATCH INTEIRO com 422, e a tela diria "salvo" com o banco intacto.
    const blocoSchema = schemaRuby.slice(schemaRuby.indexOf('  SCHEMA = {'));
    const chavesDoTopo = [
      ...blocoSchema.matchAll(/^ {6}'([a-z_]+)' => /gm),
    ].map(([, chave]) => chave);

    expect(chavesDoTopo).toContain('approach');
    expect(chavesDoTopo).toContain('triggers');

    Object.keys(DEFAULT_TRIGGERS).forEach(chave => {
      expect({
        chave,
        conhecidaPeloSchema: chavesDoTopo.includes(chave),
      }).toEqual({
        chave,
        conhecidaPeloSchema: true,
      });
    });
  });

  it('o rascunho nasce com os defaults do servidor', () => {
    expect(DEFAULT_TRIGGERS.approach).toBe(DEFAULT_APPROACH);
    expect(DEFAULT_TRIGGERS.degrade_on_return).toBe(DEFAULT_DEGRADE_ON_RETURN);
  });
});
