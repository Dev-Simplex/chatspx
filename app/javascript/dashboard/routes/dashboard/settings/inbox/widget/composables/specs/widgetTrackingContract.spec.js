import fs from 'fs';
import path from 'path';
import { DEFAULT_TRACKING } from '../widgetConfigFields';
import {
  DEFAULT_EVENT_MAP,
  PUBLIC_TRACKING_KEYS,
  TRACKING_EVENTS,
  isTestModeExpired,
  TEST_MODE_MAX_DAYS,
} from '../widgetTrackingContract';

/**
 * A tela de rastreio tem TRES contrapartes, e nenhuma delas e um arquivo desta
 * pasta. Este spec le as tres e falha nomeando o que se separou.
 */
const lerRaiz = relativo =>
  fs.readFileSync(path.resolve(process.cwd(), relativo), 'utf8');

const projecaoRuby = lerRaiz(
  'app/models/concerns/widget_tracking_projection.rb'
);
// Bloco 5.01 extraiu a varredura de segredo de `widget_configurable.rb` para um concern
// proprio. A regra continua sendo a MESMA e continua sendo a terceira fonte da verdade desta
// tela — mudou o arquivo em que ela mora, e este spec segue o arquivo.
const configuravelRuby = lerRaiz(
  'app/models/concerns/widget_secret_scanner.rb'
);
const contratoMd = lerRaiz('docs/tracking/contrato-de-eventos.md');

describe('a tela de rastreio e o servidor concordam', () => {
  it('os três arquivos foram mesmo lidos', () => {
    expect(projecaoRuby).toContain('PUBLIC_KEYS');
    expect(configuravelRuby).toContain('SECRET_KEY_PATTERN');
    expect(contratoMd).toContain('Contrato de eventos de tracking');
  });

  it('as chaves públicas da tela são as que o servidor projeta', () => {
    const doServidor = /PUBLIC_KEYS = %w\[([^\]]+)\]/
      .exec(projecaoRuby)[1]
      .trim()
      .split(/\s+/);

    expect([...PUBLIC_TRACKING_KEYS].sort()).toEqual([...doServidor].sort());
  });

  it('os doze eventos da tela são os doze do contrato, na mesma ordem', () => {
    const doContrato = [
      ...contratoMd.matchAll(/^\| \d+ \| `(chatspx_[a-z_]+)`/gm),
    ].map(([, nome]) => nome);

    expect(doContrato).toHaveLength(12);
    expect(TRACKING_EVENTS).toEqual(doContrato);
  });

  it('o mapa de fábrica cobre os doze, e nenhum a mais', () => {
    expect(Object.keys(DEFAULT_EVENT_MAP).sort()).toEqual(
      [...TRACKING_EVENTS].sort()
    );
  });

  it('nenhuma chave do rascunho de tracking cairia na recusa de segredo', () => {
    // `SECRET_KEY_PATTERN = /(\A|_)(token|secret)\z/i` — a gravacao devolve 422
    const padraoDeSegredo = /(^|_)(token|secret)$/i;

    const chaves = [
      ...Object.keys(DEFAULT_TRACKING),
      ...PUBLIC_TRACKING_KEYS,
      ...Object.keys(DEFAULT_EVENT_MAP.chatspx_lead),
    ];

    expect(chaves.filter(chave => padraoDeSegredo.test(chave))).toEqual([]);
  });

  it('o rascunho da tela não carrega chave que a projeção descartaria', () => {
    const desconhecidas = Object.keys(DEFAULT_TRACKING).filter(
      chave => !PUBLIC_TRACKING_KEYS.includes(chave)
    );

    expect(desconhecidas).toEqual([]);
  });
});

describe('o modo teste desliga sozinho', () => {
  const agora = new Date('2026-08-19T12:00:00Z').getTime();
  const diasAtras = dias =>
    new Date(agora - dias * 24 * 60 * 60 * 1000).toISOString();

  it('sete dias é o prazo, e é o do plano', () => {
    expect(TEST_MODE_MAX_DAYS).toBe(7);
  });

  it('dentro do prazo, continua ligado', () => {
    expect(isTestModeExpired(diasAtras(6), agora)).toBe(false);
    expect(isTestModeExpired(diasAtras(6.9), agora)).toBe(false);
  });

  it('passou de sete dias, expirou', () => {
    expect(isTestModeExpired(diasAtras(7.1), agora)).toBe(true);
    expect(isTestModeExpired(diasAtras(30), agora)).toBe(true);
  });

  it('sem data de início não expira — e sem data não há modo teste ligado', () => {
    expect(isTestModeExpired(null, agora)).toBe(false);
    expect(isTestModeExpired('', agora)).toBe(false);
    expect(isTestModeExpired('não é data', agora)).toBe(false);
  });
});
