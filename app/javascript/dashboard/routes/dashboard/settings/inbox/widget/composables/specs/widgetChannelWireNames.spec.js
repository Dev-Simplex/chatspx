import fs from 'fs';
import path from 'path';
import { WIDGET_CONFIG_FIELDS } from '../widgetConfigFields';

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
