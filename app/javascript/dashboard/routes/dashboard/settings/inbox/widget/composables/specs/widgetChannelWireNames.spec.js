import fs from 'fs';
import path from 'path';
import {
  WIDGET_CONFIG_FIELDS,
  WIDGET_FEATURE_CHECKBOXES,
  WIDGET_FEATURES_ELSEWHERE,
} from '../widgetConfigFields';

/**
 * O escopo `channel` do mapa canonico contra a lista REAL do servidor.
 *
 * `widgetAppearanceContract.spec.js` ja faz isto para o escopo `additional`,
 * lendo o strong params do controller. Falta a outra metade: os campos de
 * escopo `channel` nao sao permitidos pelo controller, e sim por
 * `Channel::WebWidget::EDITABLE_ATTRS`. Enquanto essa metade nao era conferida,
 * `featureFlags` viajou como `selectedFeatureFlags` — nome que o `permit` nao
 * conhece — e sumiu em silencio: 200 na resposta, toast de salvo, e o valor
 * intacto no banco.
 *
 * Le o arquivo Ruby de verdade, pelo mesmo motivo declarado la: qualquer
 * mudanca de um lado so cai aqui, nomeando o campo.
 */
const webWidgetRuby = fs.readFileSync(
  path.resolve(process.cwd(), 'app/models/channel/web_widget.rb'),
  'utf8'
);

/**
 * Os nomes declarados em `EDITABLE_ATTRS`. Ruby escreve os dois jeitos na mesma
 * lista — simbolo solto (`:widget_color`) e chave de hash aninhado
 * (`selected_feature_flags:`) —, entao a leitura junta as duas formas.
 */
const editableAttrs = () => {
  const bloco = /EDITABLE_ATTRS = \[([\s\S]*?)\]\.freeze/.exec(
    webWidgetRuby
  )[1];
  return [
    ...new Set([
      ...[...bloco.matchAll(/:([a-z_][a-z0-9_]*)/g)].map(m => m[1]),
      ...[...bloco.matchAll(/([a-z_][a-z0-9_]*):/g)].map(m => m[1]),
    ]),
  ];
};

const camposDoCanal = WIDGET_CONFIG_FIELDS.filter(f => f.scope === 'channel');

describe('os campos de escopo `channel` usam o nome de fio do servidor', () => {
  it('o arquivo do servidor foi mesmo lido — senão o teste passaria vazio', () => {
    expect(webWidgetRuby).toContain('class Channel::WebWidget');
    // ancoras: se a leitura quebrar, ela devolve lista vazia e TUDO passaria
    expect(editableAttrs()).toEqual(
      expect.arrayContaining([
        'website_url',
        'widget_color',
        'pre_chat_form_options',
        'selected_feature_flags',
      ])
    );
    expect(camposDoCanal.length).toBeGreaterThanOrEqual(5);
  });

  it.each(camposDoCanal)(
    '`$key` viaja como `$path`, que está em EDITABLE_ATTRS',
    field => {
      expect(editableAttrs()).toContain(field.path);
    }
  );
});

/* ── Bloco 4.11: as caixas de recurso contra as flags do canal ────────────────
 *
 * A armadilha, medida nesta base: a flag existe de um lado e nao do outro. O
 * recurso fica invisivel para sempre — sem erro, sem log e sem teste vermelho,
 * porque nenhum lado sozinho sabe da existencia do outro. Foi exatamente o que
 * aconteceu com o som: `IFrameHelper.isNotificationSoundEnabled` ja consultava
 * `notification_sound` em `enabledFeatures`, e `has_flags` nao tinha a flag;
 * `selected_feature_flags=` respondia `ArgumentError: Invalid flag
 * "notification_sound"`, e o som ficou desligado em toda inbox da frota, sem
 * caminho nenhum para ligar.
 *
 * A guarda vale nos DOIS sentidos, porque cada sentido quebra diferente:
 *   · flag no Ruby e ausente na tela  -> recurso que ninguem consegue ligar;
 *   · caixa na tela e ausente no Ruby -> `ArgumentError` no PATCH ao salvar.
 * Por isso a comparacao e de conjunto, e nao `arrayContaining`.
 *
 * `allow_mobile_webview` fica fora da lista de caixas de proposito: tem
 * interruptor proprio em `settingsPage/ConfigurationPage.vue` (e configuracao de
 * instalacao, nao recurso do widget). Ficar de fora e DECLARACAO, nao
 * esquecimento — por isso ele mora em `WIDGET_FEATURES_ELSEWHERE`, e o que tem
 * de fechar com o Ruby e a soma das duas listas.
 */
/**
 * A leitura tira as linhas de comentario ANTES de procurar as flags, e isso foi
 * medido: com o `6 => :notification_sound` apenas comentado no Ruby, a versao
 * ingenua deste leitor continuou verde — ela lia o comentario como declaracao,
 * e a guarda inteira nao servia para nada. O `default` no argumento existe para
 * o exemplo abaixo poder alimentar uma fonte de mentira e cobrar a diferenca.
 */
const flagsDoRuby = (fonte = webWidgetRuby) => {
  const semComentario = fonte
    .split('\n')
    .filter(linha => !/^\s*#/.test(linha))
    .join('\n');
  const bloco = /has_flags ([\s\S]*?):column =>/.exec(semComentario)[1];
  return [...bloco.matchAll(/\d+\s*=>\s*:([a-z_][a-z0-9_]*)/g)].map(m => m[1]);
};

describe('4.11 — as caixas de recurso batem com as flags do canal', () => {
  it('o `has_flags` foi mesmo lido — senão a lista vem vazia e tudo passa', () => {
    expect(webWidgetRuby).toContain('has_flags');
    expect(flagsDoRuby()).toContain('attachments');
    expect(flagsDoRuby().length).toBeGreaterThanOrEqual(5);
  });

  it('flag comentada NÃO conta como declarada', () => {
    const fonteDeMentira = [
      'has_flags 1 => :attachments,',
      '            # 6 => :notification_sound,',
      "            :column => 'feature_flags'",
    ].join('\n');

    expect(flagsDoRuby(fonteDeMentira)).toEqual(['attachments']);
  });

  it('nenhuma flag do servidor fica sem lugar na tela, e vice-versa', () => {
    expect(
      [...WIDGET_FEATURE_CHECKBOXES, ...WIDGET_FEATURES_ELSEWHERE].sort()
    ).toEqual(flagsDoRuby().sort());
  });

  it('`notification_sound` existe dos dois lados — é o que o SDK consulta', () => {
    // O consumidor: `IFrameHelper.isNotificationSoundEnabled` lê exatamente
    // esta string de `enabledFeatures`. Nome divergente de um lado e o som
    // volta a ser inligável.
    expect(WIDGET_FEATURE_CHECKBOXES).toContain('notification_sound');
    expect(flagsDoRuby()).toContain('notification_sound');
  });
});
