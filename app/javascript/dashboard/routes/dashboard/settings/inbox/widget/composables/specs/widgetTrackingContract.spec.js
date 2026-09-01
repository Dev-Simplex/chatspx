import fs from 'fs';
import path from 'path';
import { DEFAULT_TRACKING } from '../widgetConfigFields';
import {
  DEFAULT_EVENT_MAP,
  PUBLIC_TRACKING_KEYS,
  TRACKING_EVENTS,
  isTestModeExpired,
  TEST_MODE_MAX_DAYS,
  TRACKING_LIMITS,
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

/**
 * Bloco 5.01 — "não configurado" tem de querer dizer a MESMA coisa nos dois lados.
 *
 * A tela nasce com os quatro escalares em string vazia e, por `tracking` ser campo de
 * grupo, `buildPayload` manda o objeto INTEIRO a cada salvamento. O servidor recusava
 * isso com quatro erros de pattern/enum — 422 no primeiro salvamento de toda inbox
 * nova. O conserto mora em `WidgetTrackingSchema.normalize` (vazio vira ausência), e
 * este bloco existe para que os dois lados não voltem a se separar em silêncio.
 */
describe('vazio na tela é "não configurado" no servidor', () => {
  const schemaRuby = lerRaiz('app/models/concerns/widget_tracking_schema.rb');
  const modeloRuby = lerRaiz('app/models/concerns/widget_configurable.rb');

  // Os escalares que o servidor poda: `SCALAR_KEYS` sai de `SCHEMA['properties']` —
  // a RAIZ, e só ela. Por isso este recorte é do bloco do `SCHEMA` e não do arquivo
  // inteiro: `lead_value.mode` também é `'type' => 'string'`, mas mora dentro de
  // `LEAD_VALUE_OBJECT` e NÃO é podável (podá-lo apagaria a escolha do administrador
  // em vez de ler um campo vazio). Varrer o arquivo todo achava cinco chaves e
  // descrevia um servidor que não existe.
  const blocoSchema = /SCHEMA = \{(.+?)\n {2}\}\.freeze/s.exec(schemaRuby)[1];
  const escalaresDoServidor = [
    ...blocoSchema.matchAll(/'(\w+)' => \{ 'type' => 'string'/g),
  ].map(([, nome]) => nome);

  it('o servidor tem mesmo a poda — senão os exemplos abaixo não medem nada', () => {
    expect(schemaRuby).toContain('def normalize(tracking)');
    expect(schemaRuby).toContain('SCALAR_KEYS');
    expect(modeloRuby).toContain(
      'before_validation :normalize_widget_tracking'
    );
    expect(escalaresDoServidor).toHaveLength(4);
  });

  it('as chaves que a tela manda VAZIAS são exatamente as que o servidor poda', () => {
    // Se alguém acrescentar um quinto campo de texto ao rascunho de fábrica sem
    // declará-lo `type: string` no schema, ele volta a dar 422 no primeiro
    // salvamento — e este exemplo cai antes de o cliente descobrir.
    const vaziasNaTela = Object.entries(DEFAULT_TRACKING)
      .filter(([, valor]) => valor === '')
      .map(([nome]) => nome);

    expect([...vaziasNaTela].sort()).toEqual([...escalaresDoServidor].sort());
  });
});

/**
 * A outra metade do mesmo defeito: a tela valida FORMATO por conta dela
 * (`TRACKING_LIMITS`) e o servidor valida por outro conjunto de padrões. Divergir é
 * inevitável; o que não pode acontecer é divergir para o lado PERIGOSO — a tela
 * aceitar e deixar salvar um valor que o servidor recusa, porque aí o administrador
 * leva um 422 sobre um campo que a própria tela disse estar certo.
 */
describe('o que a tela ACEITA, o servidor aceita', () => {
  const schemaRuby = lerRaiz('app/models/concerns/widget_tracking_schema.rb');
  const padraoDoServidor = nome =>
    new RegExp(new RegExp(`${nome} = '(.+?)'\\.freeze`).exec(schemaRuby)[1]);

  const pares = [
    [
      'meta_pixel_id',
      TRACKING_LIMITS.metaPixelIdPattern,
      padraoDoServidor('META_PIXEL_ID_PATTERN'),
      ['123456789012345', '1234567890123456', '1234567890', '123', 'EAAGm0PX'],
    ],
    [
      'ga4_measurement_id',
      TRACKING_LIMITS.ga4MeasurementIdPattern,
      padraoDoServidor('GA4_MEASUREMENT_ID_PATTERN'),
      ['G-ABC1234567', 'G-AbC1234567', 'G-ABC12', 'UA-123456'],
    ],
    [
      'google_ads_send_to',
      TRACKING_LIMITS.googleAdsSendToPattern,
      padraoDoServidor('GOOGLE_ADS_SEND_TO_PATTERN'),
      ['AW-123456789/AbC-D_efGh12', 'AW-123456789', 'AW-123456789/ab', 'AW'],
    ],
  ];

  it('os padrões do servidor foram mesmo lidos', () => {
    // `RegExp#source` escapa a barra, então a comparação é com o padrão já escapado —
    // e não com o texto do arquivo Ruby.
    expect(pares.map(([, , servidor]) => servidor.source)).toEqual([
      '^[0-9]{1,20}$',
      '^G-[A-Za-z0-9]{1,20}$',
      '^AW-[0-9]{1,15}(\\/[A-Za-z0-9_-]{1,40})?$',
    ]);
  });

  it.each(pares)(
    '%s: nenhum valor passa na tela para levar 422 no servidor',
    (_nome, front, servidor, amostras) => {
      const perigosos = amostras.filter(
        valor => front.test(valor) && !servidor.test(valor)
      );

      expect(perigosos).toEqual([]);
    }
  );

  it('e a assimetria é a segura: hoje a tela é ESTRITAMENTE mais rígida', () => {
    // Medido, não afirmado. A tela recusa valores que o servidor aceitaria — entre
    // eles `AW-123456789`, que é um ID de conversão do Google Ads sem rótulo e é
    // legítimo. Isso é um falso NEGATIVO na tela (o administrador não consegue
    // digitar um valor válido), e o conserto é da Tela 4 (bloco 5.06), não do
    // schema. Este exemplo fixa o número para que a lista não cresça sem que
    // alguém veja.
    const recusadosSoPelaTela = pares.flatMap(
      ([nome, front, servidor, amostras]) =>
        amostras
          .filter(valor => !front.test(valor) && servidor.test(valor))
          .map(valor => `${nome}=${valor}`)
    );

    expect(recusadosSoPelaTela).toEqual([
      'meta_pixel_id=1234567890',
      'meta_pixel_id=123',
      'ga4_measurement_id=G-AbC1234567',
      'ga4_measurement_id=G-ABC12',
      'google_ads_send_to=AW-123456789',
      'google_ads_send_to=AW-123456789/ab',
    ]);
  });
});
