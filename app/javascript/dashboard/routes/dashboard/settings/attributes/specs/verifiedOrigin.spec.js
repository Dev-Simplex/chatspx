import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import AddAttribute from '../AddAttribute.vue';
import EditAttribute from '../EditAttribute.vue';

// Bloco 4.17 — a terceira ponta do "ingravavel": permit e jbuilder sao medidos no rspec,
// e aqui se mede a tela. Sem campo no formulario a flag continua existindo so no console,
// que e onde ela estava.
//
// O segundo teste e o que importa mais. O formulario de EDICAO e de SUBSTITUICAO: ele
// remonta o objeto inteiro e o reenvia. Se a flag nao for lida do registro no `mounted`,
// o campo nasce `false` e o primeiro salvamento de qualquer edicao — trocar uma virgula da
// descricao — manda `requires_verified_origin: false` e DESLIGA a protecao. O portao
// continuaria correto e a trava sumiria sozinha.

const dispatch = vi.fn();

const mountOpts = {
  global: {
    mocks: {
      $t: chave => chave,
      $store: { dispatch, getters: { getUIFlags: {} } },
    },
    stubs: {
      'woot-modal': { template: '<div><slot /></div>' },
      'woot-modal-header': true,
      'woot-input': true,
      NextButton: true,
      TagInput: true,
    },
  },
};

beforeEach(() => dispatch.mockClear());

describe('AddAttribute', () => {
  it('renderiza o campo de origem verificada', () => {
    const wrapper = mount(AddAttribute, mountOpts);

    expect(
      wrapper.find('[data-testid="requires-verified-origin"]').exists()
    ).toBe(true);
  });

  it('manda a flag ligada quando o campo e marcado', async () => {
    const wrapper = mount(AddAttribute, mountOpts);
    wrapper.setData({
      displayName: 'CPF',
      description: 'documento',
      attributeKey: 'cpf',
    });
    await wrapper
      .find('[data-testid="requires-verified-origin"]')
      .setValue(true);

    await wrapper.vm.addAttributes();

    expect(dispatch).toHaveBeenCalledWith(
      'attributes/create',
      expect.objectContaining({ requires_verified_origin: true })
    );
  });

  // Controle: sem marcar o campo, a flag vai `false` — e nao `undefined`. `undefined`
  // sumiria no JSON e o registro nasceria com a coluna nula, o que e um terceiro estado
  // que ninguem pediu.
  it('manda a flag desligada quando o campo nao e marcado', async () => {
    const wrapper = mount(AddAttribute, mountOpts);
    wrapper.setData({
      displayName: 'CPF',
      description: 'documento',
      attributeKey: 'cpf',
    });

    await wrapper.vm.addAttributes();

    expect(dispatch).toHaveBeenCalledWith(
      'attributes/create',
      expect.objectContaining({ requires_verified_origin: false })
    );
  });
});

describe('EditAttribute', () => {
  const attribute = protegida => ({
    id: 7,
    attribute_display_name: 'CPF',
    attribute_description: 'documento',
    attribute_display_type: 'text',
    attribute_key: 'cpf',
    attribute_values: [],
    regex_pattern: null,
    regex_cue: null,
    requires_verified_origin: protegida,
  });

  // `setFormValues` roda no `mounted`, entao o DOM so reflete o registro no tick
  // seguinte. Sem o `nextTick` o teste leria o checkbox antes do flush e reprovaria
  // um componente correto.
  const montaEdicao = async protegida => {
    const wrapper = mount(EditAttribute, {
      ...mountOpts,
      props: { selectedAttribute: attribute(protegida) },
    });
    await nextTick();
    return wrapper;
  };

  it('carrega o campo marcado quando a definicao ja e protegida', async () => {
    const wrapper = await montaEdicao(true);

    expect(
      wrapper.find('[data-testid="requires-verified-origin"]').element.checked
    ).toBe(true);
  });

  it('NAO desliga a protecao num salvamento que nao tocou no campo', async () => {
    const wrapper = await montaEdicao(true);

    await wrapper.vm.editAttributes();

    expect(dispatch).toHaveBeenCalledWith(
      'attributes/update',
      expect.objectContaining({ requires_verified_origin: true })
    );
  });

  // Controle positivo do par: desmarcar tem de DESLIGAR de verdade. Sem ele, um `mounted`
  // que ignorasse o campo e mandasse `true` sempre passaria no teste de cima.
  it('desliga a protecao quando o campo e desmarcado', async () => {
    const wrapper = await montaEdicao(true);
    await wrapper
      .find('[data-testid="requires-verified-origin"]')
      .setValue(false);

    await wrapper.vm.editAttributes();

    expect(dispatch).toHaveBeenCalledWith(
      'attributes/update',
      expect.objectContaining({ requires_verified_origin: false })
    );
  });

  it('mantem desligada a definicao que nunca foi protegida', async () => {
    const wrapper = await montaEdicao(false);

    await wrapper.vm.editAttributes();

    expect(dispatch).toHaveBeenCalledWith(
      'attributes/update',
      expect.objectContaining({ requires_verified_origin: false })
    );
  });
});
