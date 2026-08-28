import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import CustomAttributes from '../CustomAttributes.vue';

const attributesByModel = vi.fn();
const dispatch = vi.fn();
const selectedChat = { value: { id: 1, custom_attributes: {} } };
const uiSettings = { value: {} };

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: (...args) => dispatch(...args) }),
  useStoreGetters: () => ({
    getSelectedChat: selectedChat,
    'attributes/getAttributesByModel': {
      value: (...args) => attributesByModel(...args),
    },
    // Este arquivo mede o caminho de CONVERSA; o registro de contato entra vazio,
    // como `getContact` devolve para id desconhecido. A forma real da store de
    // contatos (chave do topo camelizada) esta medida em
    // `CustomAttributes.contactStore.spec.js`, com a mutation de verdade.
    'contacts/getContact': { value: () => ({}) },
  }),
}));

vi.mock('vue-router', () => ({ useRoute: () => ({ params: {} }) }));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings, updateUISettings: vi.fn() }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const definition = (key, overrides = {}) => ({
  id: key,
  attribute_key: key,
  attribute_display_name: key,
  attribute_display_type: 'text',
  attribute_values: [],
  attribute_description: '',
  auto_provisioned_from_website: false,
  ...overrides,
});

const mountAttributes = () =>
  mount(CustomAttributes, {
    props: { attributeFrom: 'conversation_panel' },
    global: {
      stubs: {
        Draggable: { template: '<div />' },
        CustomAttribute: {
          props: ['label'],
          template: '<div class="attr">{{ label }}</div>',
        },
      },
    },
  });

describe('CustomAttributes — secao "Dados recebidos do site"', () => {
  beforeEach(() => {
    attributesByModel.mockReset();
    dispatch.mockReset();
    selectedChat.value = { id: 1, custom_attributes: {} };
  });

  it('nao desenha a secao quando nenhum atributo veio do site', () => {
    attributesByModel.mockReturnValue([definition('plano')]);

    const wrapper = mountAttributes();

    expect(
      wrapper.find('[data-testid="from-website-section-title"]').exists()
    ).toBe(false);
    expect(
      wrapper.findAll('[data-testid="from-website-attribute"]')
    ).toHaveLength(0);
  });

  // Os valores no jsonb da conversa nao sao enfeite: a secao lista o que ESTE
  // registro recebeu do site, nao toda definicao marcada na conta. Sem eles, o
  // titulo prometeria "(2)" para um contato que nunca mandou nada.
  it('desenha a secao com a contagem correta e um selo por atributo', () => {
    attributesByModel.mockReturnValue([
      definition('plano'),
      definition('carrinho_valor', { auto_provisioned_from_website: true }),
      definition('cupom', { auto_provisioned_from_website: true }),
    ]);
    selectedChat.value = {
      id: 1,
      custom_attributes: { carrinho_valor: 4200, cupom: 'BLACKFRIDAY' },
    };

    const wrapper = mountAttributes();

    expect(
      wrapper.find('[data-testid="from-website-section-title"]').text()
    ).toBe('Data received from the website (2)');
    expect(
      wrapper.findAll('[data-testid="from-website-attribute"]')
    ).toHaveLength(2);

    const badges = wrapper.findAll('[data-testid="from-website-badge"]');
    expect(badges).toHaveLength(2);
    expect(badges[0].text()).toBe('From the website');
  });

  it('a contagem acompanha o numero de atributos do site, nao o total', () => {
    attributesByModel.mockReturnValue([
      definition('a'),
      definition('b'),
      definition('c'),
      definition('d', { auto_provisioned_from_website: true }),
    ]);
    selectedChat.value = { id: 1, custom_attributes: { d: 'veio do site' } };

    const wrapper = mountAttributes();

    expect(
      wrapper.find('[data-testid="from-website-section-title"]').text()
    ).toBe('Data received from the website (1)');
  });
  // "aparece na mesma sessao": com o painel ja aberto, uma chave nova no jsonb
  // precisa provocar uma nova busca das definicoes — senao o valor chega e nada
  // renderiza, porque a lista renderizada e a de definicoes.
  it('pede as definicoes de novo quando o jsonb traz chave que nenhuma definicao conhece', async () => {
    attributesByModel.mockReturnValue([definition('plano')]);
    selectedChat.value = {
      id: 1,
      custom_attributes: { plano: 'pro', carrinho_valor: 4200 },
    };

    mountAttributes();
    await Promise.resolve();

    expect(dispatch).toHaveBeenCalledWith('attributes/get', 0);
  });

  it('nao pede de novo quando toda chave do jsonb ja tem definicao', async () => {
    attributesByModel.mockReturnValue([definition('plano')]);
    selectedChat.value = { id: 1, custom_attributes: { plano: 'pro' } };

    mountAttributes();
    await Promise.resolve();

    expect(dispatch).not.toHaveBeenCalledWith('attributes/get', 0);
  });
});
