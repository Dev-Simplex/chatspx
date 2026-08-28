import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import { getters as contactsGetters } from 'dashboard/store/modules/contacts/getters';
import { mutations as contactsMutations } from 'dashboard/store/modules/contacts/mutations';
import types from 'dashboard/store/mutation-types';
import CustomAttributes from '../CustomAttributes.vue';

/**
 * Bloco 1.17 — o aceite literal, pelo caminho de verdade.
 *
 * ── POR QUE ESTE ARQUIVO EXISTE, JA HAVENDO `CustomAttributes.spec.js` ──────────────
 *
 * O aceite do bloco e `setCustomAttributes({ carrinho_valor: 4200 })`, e esse metodo do
 * SDK e o de CONTATO: `widget/api/contacts.js:18` manda `PATCH /api/v1/widget/contact`
 * com `custom_attributes`. O painel recebe a mudanca pelo websocket
 * (`action_cable_listener.rb:228` → `contact.push_event_data`, snake_case) e a store de
 * contatos guarda o registro por `EDIT_CONTACT`, que passa tudo por
 * `camelcaseKeys(..., { stopPaths: ['custom_attributes'] })`.
 *
 * O `stopPaths` protege o CONTEUDO e nao a CHAVE do topo — entao o registro guarda
 * `customAttributes` com `carrinho_valor` intacto dentro (fixado em
 * `contact/specs/siteContextStoreShape.spec.js`). Enquanto o componente lia so
 * `contact.custom_attributes`, o valor era `undefined` para todo contato: a secao nao
 * aparecia e o watch do "na mesma sessao" nunca disparava.
 *
 * O spec vizinho nao pegava isso porque dubla o getter com
 * `{ custom_attributes: {} }` — uma forma que a store de contatos nunca produz. Aqui a
 * store e a de verdade: `getters` e `mutations` importados do modulo, e o payload
 * entrando pela mutation, com as chaves como o backend as escreve.
 */

const attributesGet = vi.fn();

vi.mock('vue-router', () => ({ useRoute: () => ({ params: {} }) }));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: { value: {} },
    updateUISettings: vi.fn(),
  }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const CONTACT_ID = 7;

// A forma do `_custom_attribute_definition.json.jbuilder` — nao uma invencao do teste.
const definition = (key, model = 'contact_attribute') => ({
  id: key,
  attribute_display_name: key,
  attribute_display_type: 'text',
  attribute_description: '',
  auto_provisioned_from_website: false,
  attribute_key: key,
  regex_pattern: null,
  regex_cue: null,
  attribute_values: [],
  attribute_model: model,
  default_value: null,
});

const websiteDefinition = (key, model = 'contact_attribute') => ({
  ...definition(key, model),
  attribute_description: 'Received from the website',
  auto_provisioned_from_website: true,
});

// A forma do `Contact#push_event_data` — o que o websocket entrega ao painel.
const pushEventData = customAttributes => ({
  additional_attributes: { created_at_ip: '203.0.113.77' },
  custom_attributes: customAttributes,
  email: 'ana@acme.com.br',
  id: CONTACT_ID,
  identifier: 'CRM-4711',
  name: 'Ana Souza',
  phone_number: null,
  thumbnail: '',
  blocked: false,
  type: 'contact',
});

const buildStore = (definitions, chatCustomAttributes = {}) => {
  const store = createStore({
    getters: {
      // O painel do contato e aberto de dentro da conversa: e por `meta.sender.id`
      // que o componente descobre de quem sao os atributos. A conversa entra crua,
      // como a store de conversas a guarda — ela nao passa por `camelcaseKeys`.
      getSelectedChat: () => ({
        id: 42,
        custom_attributes: chatCustomAttributes,
        meta: { sender: { id: CONTACT_ID } },
      }),
    },
    modules: {
      contacts: {
        namespaced: true,
        state: { records: {}, sortOrder: [], uiFlags: {}, appliedFilters: [] },
        getters: contactsGetters,
        mutations: contactsMutations,
      },
      attributes: {
        namespaced: true,
        state: { records: definitions },
        getters: {
          getAttributesByModel: state => model =>
            state.records.filter(item => item.attribute_model === model),
        },
        actions: { get: (...args) => attributesGet(...args) },
      },
    },
  });

  return store;
};

const mountPanel = (store, attributeType = 'contact_attribute') =>
  mount(CustomAttributes, {
    props: {
      attributeType,
      attributeFrom: 'conversation_contact_panel',
      contactId: CONTACT_ID,
    },
    global: {
      plugins: [store],
      stubs: {
        Draggable: { template: '<div />' },
        CustomAttribute: {
          props: ['label', 'value'],
          template: '<div class="attr">{{ label }}={{ value }}</div>',
        },
      },
    },
  });

describe('1.17 — atributo que o site mandou, entrando pela store de contatos', () => {
  beforeEach(() => {
    attributesGet.mockReset();
  });

  it('`setCustomAttributes({ carrinho_valor: 4200 })` aparece no painel, com o valor', () => {
    const store = buildStore([websiteDefinition('carrinho_valor')]);
    store.commit(
      `contacts/${types.EDIT_CONTACT}`,
      pushEventData({ carrinho_valor: 4200 })
    );

    const wrapper = mountPanel(store);

    expect(
      wrapper.find('[data-testid="from-website-section-title"]').text()
    ).toBe('Data received from the website (1)');
    const linhas = wrapper.findAll('[data-testid="from-website-attribute"]');
    expect(linhas).toHaveLength(1);
    expect(linhas[0].find('.attr').text()).toBe('carrinho_valor=4200');
  });

  /**
   * A contraprova exigida pelo enunciado: a assercao positiva acima passaria tambem se
   * o componente lesse a grafia camelizada por acaso. Este caso FORCA a condicao ruim —
   * o registro so tem a grafia que a store escreve — e mede que a leitura da chave crua
   * nao voltou sozinha.
   */
  it('a store guarda `customAttributes`, nao `custom_attributes` — e o painel le mesmo assim', () => {
    const store = buildStore([websiteDefinition('cupom')]);
    store.commit(
      `contacts/${types.EDIT_CONTACT}`,
      pushEventData({ cupom: 'BLACKFRIDAY' })
    );

    const registro = store.getters['contacts/getContact'](CONTACT_ID);
    expect(registro.custom_attributes).toBeUndefined();
    expect(registro.customAttributes.cupom).toBe('BLACKFRIDAY');

    const wrapper = mountPanel(store);

    expect(
      wrapper.find('[data-testid="from-website-attribute"] .attr').text()
    ).toBe('cupom=BLACKFRIDAY');
  });

  /**
   * "Na mesma sessao": com o painel JA ABERTO, o valor chega pelo websocket e a definicao
   * nao — e sem definicao nada renderiza. O componente pede a lista de novo ao ver no
   * jsonb uma chave que nenhuma definicao conhece. Lendo a grafia errada, `Object.keys`
   * rodava sempre sobre `{}` e o pedido nunca saia.
   */
  it('chave nova chegando com o painel aberto pede as definicoes de novo', async () => {
    const store = buildStore([definition('plano')]);
    store.commit(
      `contacts/${types.EDIT_CONTACT}`,
      pushEventData({ plano: 'ouro' })
    );

    mountPanel(store);
    await nextTick();
    expect(attributesGet).not.toHaveBeenCalled();

    store.commit(
      `contacts/${types.EDIT_CONTACT}`,
      pushEventData({ plano: 'ouro', carrinho_valor: 4200 })
    );
    await nextTick();

    expect(attributesGet).toHaveBeenCalled();
  });

  /**
   * A definicao e da CONTA inteira: uma chave que outro contato mandou tem definicao aqui
   * tambem. Contando definicao em vez do que este contato recebeu, o titulo prometia
   * "Dados recebidos do site (1)" com a linha vazia embaixo.
   */
  it('definicao do site que ESTE contato nunca recebeu nao entra na secao nem na contagem', () => {
    const store = buildStore([
      websiteDefinition('carrinho_valor'),
      websiteDefinition('cupom'),
    ]);
    store.commit(
      `contacts/${types.EDIT_CONTACT}`,
      pushEventData({ carrinho_valor: 4200 })
    );

    const wrapper = mountPanel(store);

    expect(
      wrapper.find('[data-testid="from-website-section-title"]').text()
    ).toBe('Data received from the website (1)');
    expect(
      wrapper.findAll('[data-testid="from-website-attribute"]')
    ).toHaveLength(1);
  });

  /**
   * O agente pode limpar o valor de uma linha recebida do site. A chave continua no jsonb,
   * entao a linha continua na tela — senao editar para vazio faria a linha sumir e o
   * agente perderia o caminho de volta.
   */
  it('valor esvaziado pelo agente mantem a linha, porque a chave continua no jsonb', () => {
    const store = buildStore([websiteDefinition('carrinho_valor')]);
    store.commit(
      `contacts/${types.EDIT_CONTACT}`,
      pushEventData({ carrinho_valor: '' })
    );

    const wrapper = mountPanel(store);

    expect(
      wrapper.findAll('[data-testid="from-website-attribute"]')
    ).toHaveLength(1);
  });

  /**
   * A store de CONVERSAS nao cameliza — guarda o payload cru da API, e e de la que sai
   * `getSelectedChat`. A correcao nao pode ter trocado uma grafia pela outra: as duas tem
   * de funcionar, e e por isso que este caso mora no mesmo arquivo.
   */
  it('a grafia crua continua sendo lida — a store de conversas nao cameliza', () => {
    const store = buildStore(
      [websiteDefinition('carrinho_valor', 'conversation_attribute')],
      { carrinho_valor: 4200 }
    );

    const wrapper = mountPanel(store, 'conversation_attribute');

    expect(
      wrapper.find('[data-testid="from-website-attribute"] .attr').text()
    ).toBe('carrinho_valor=4200');
  });
});
