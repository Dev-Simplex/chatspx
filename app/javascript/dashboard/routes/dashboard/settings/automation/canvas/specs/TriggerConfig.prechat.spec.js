/**
 * BLOCO 4.02 — O EDITOR DO GATILHO DIZ A VERDADE SOBRE O FLUXO DE CAPTURA.
 *
 * `TriggerConfig#kind` caía em `'event'` para qualquer `trigger_kind` desconhecido, então um fluxo
 * de captura era exibido como "Um evento da conversa". Duas consequências, e a segunda é a cara:
 * o admin lê uma mentira sobre o fluxo que está editando; e mexer no seletor (achando que estava
 * escolhendo um evento) emitia `trigger_kind: 'event'` e convertia o fluxo de captura de verdade.
 *
 * A captura não é oferecida como CONVERSÃO: ela só aparece na lista quando o nó já é de captura.
 * O canvas não tem editor de segmentação, e um fluxo de captura sem alvo é um catch-all que
 * assume o pré-chat da conta inteira.
 */
import { shallowMount } from '@vue/test-utils';
import TriggerConfig from '../config/TriggerConfig.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// O `TriggerConfig` passou a chamar `useAutomation()`, e o composable resolve os getters por
// `getCurrentInstance().proxy.$store` (`composables/store.js`). Sem um `$store` o setup morre em
// "Cannot read properties of undefined (reading 'getters')" ANTES de renderizar o seletor, e os
// seis exemplos deste arquivo param de medir o que medem.
//
// Instalado como PLUGIN, e não por `global.mocks`: `mocks` chega tarde demais para o
// `getCurrentInstance()` do setup (medido — com `mocks` os seis continuam no mesmo TypeError).
// `attributes/getAttributes` é o único getter que precisa EXISTIR: nos modos `event` e `keyword`
// o editor monta o seletor de condição, e `useAutomationValues#getConditionDropdownValues` lê
// `.value` dele sem guarda. Os demais podem faltar (`useMapGetter` devolve um computed vazio).
// Nenhuma asserção deste arquivo depende do conteúdo: o que se mede é a lista de MODOS, local ao
// componente.
const storePlugin = {
  install(app) {
    app.config.globalProperties.$store = {
      getters: { 'attributes/getAttributes': [] },
    };
  },
};

// `renderStubDefaultSlot` porque o seletor de modo vive DENTRO do slot do `ConfigField`, e um
// stub não renderiza o slot por padrão — sem isto o `SingleSelect` não existe na árvore montada e
// o spec mediria a ausência dele, não a lista de modos.
const montar = node =>
  shallowMount(TriggerConfig, {
    props: { node: { id: 'trg', type: 'trigger', ...node } },
    global: {
      mocks: { t: key => key },
      plugins: [storePlugin],
      renderStubDefaultSlot: true,
    },
  });

// O PRIMEIRO SingleSelect do editor é o seletor de MODO do gatilho (os outros são evento,
// direção e correspondência) — é a lista dele que este spec inspeciona.
const opcoes = wrapper =>
  wrapper.findAllComponents(SingleSelect)[0].props('options');

describe('4.02 — o gatilho de captura no editor do canvas', () => {
  it('mostra a captura como o modo do fluxo, e não "evento"', () => {
    const wrapper = montar({ trigger_kind: 'widget_prechat' });

    expect(opcoes(wrapper).map(o => o.id)).toContain('widget_prechat');
    expect(
      wrapper.find('[data-testid="trigger-widget-prechat-hint"]').exists()
    ).toBe(true);
  });

  it('explica onde a segmentação é editada, já que não é aqui', () => {
    const wrapper = montar({ trigger_kind: 'widget_prechat' });

    expect(
      wrapper.find('[data-testid="trigger-widget-prechat-hint"]').text()
    ).toBe('AUTOMATION.CANVAS.CONFIG.TRIGGER.WIDGET_PRECHAT_HINT');
  });

  // CONTROLE — nos outros gatilhos nada muda, e a captura NÃO é oferecida como destino.
  it.each([
    ['event', undefined],
    ['keyword', 'keyword'],
    ['schedule', 'schedule'],
    ['webhook', 'webhook'],
  ])('não oferece a captura como conversão a partir de %s', (_rotulo, kind) => {
    const wrapper = montar(kind ? { trigger_kind: kind } : {});

    expect(opcoes(wrapper).map(o => o.id)).not.toContain('widget_prechat');
    expect(
      wrapper.find('[data-testid="trigger-widget-prechat-hint"]').exists()
    ).toBe(false);
  });
});
