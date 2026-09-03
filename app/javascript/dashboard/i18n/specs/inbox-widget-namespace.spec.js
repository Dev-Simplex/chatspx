import en from '../locale/en';
import ptBR from '../locale/pt_BR';

// Mecanismo do aceite do bloco 0.7 (§2.2): "inboxWidget.json existe nos dois
// idiomas" e as 2 chaves orfas (D7) sairam. Asserta o objeto de mensagens que o
// vue-i18n realmente recebe, nao a existencia do arquivo em disco: e o runtime
// que quebra quando alguem esquece de registrar o namespace no index.js.
const LOCALES = [
  ['en', en],
  ['pt_BR', ptBR],
];

describe('namespace i18n inboxWidget (bloco 0.7)', () => {
  it.each(LOCALES)(
    'registra INBOX_WIDGET nas mensagens de %s',
    (_name, messages) => {
      expect(messages.INBOX_WIDGET).toBeTypeOf('object');
    }
  );

  it.each(LOCALES)(
    'nao expoe mais as chaves orfas INBOX_MGMT.TABS.{CAMPAIGN,WIDGET_BUILDER} em %s',
    (_name, messages) => {
      const tabs = messages.INBOX_MGMT.TABS;
      expect(Object.keys(tabs)).not.toContain('CAMPAIGN');
      expect(Object.keys(tabs)).not.toContain('WIDGET_BUILDER');
    }
  );

  it.each(LOCALES)(
    'preserva o bloco vivo INBOX_MGMT.WIDGET_BUILDER, usado pelo preview do widget, em %s',
    (_name, messages) => {
      // Settings.vue:1111+ e widget-preview/Widget.vue leem daqui. O bloco de
      // primeiro nivel homonimo NAO e orfao — so as duas chaves de TABS eram.
      expect(
        messages.INBOX_MGMT.WIDGET_BUILDER.WIDGET_OPTIONS
          .WIDGET_BUBBLE_POSITION_LABEL
      ).toBeTypeOf('string');
    }
  );
});
