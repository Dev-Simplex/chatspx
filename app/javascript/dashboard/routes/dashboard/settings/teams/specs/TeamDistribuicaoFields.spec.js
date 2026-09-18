import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import TeamDistribuicaoFields from '../TeamDistribuicaoFields.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const showSpy = vi.fn();
const updateSpy = vi.fn();
vi.mock('dashboard/api/teamDistribuicao', () => ({
  default: {
    show: (...args) => showSpy(...args),
    update: (...args) => updateSpy(...args),
  },
}));

const resposta = {
  data: {
    configurado: true,
    politica: { ativo: true, modo: 'rodizio' },
    pool: [
      {
        user_id: 9,
        ativo: true,
        suspenso_ate: null,
        motivo: null,
        cap: 2,
        produtos: [],
      },
    ],
    candidatos: [],
    time: { nome: 'Vendas' },
  },
};

const montar = (props = {}) =>
  mount(TeamDistribuicaoFields, {
    props: { teamId: 7, embutido: true, ...props },
    global: {
      mocks: { $t: chave => chave },
      stubs: { Spinner: true, NextButton: true },
    },
  });

describe('TeamDistribuicaoFields salvar', () => {
  beforeEach(() => {
    showSpy.mockReset();
    updateSpy.mockReset().mockResolvedValue(resposta);
    vi.mocked(useAlert).mockReset();
  });

  it('nao salva nem avisa enquanto o show ainda esta pendente', async () => {
    showSpy.mockReturnValue(new Promise(() => {}));
    const wrapper = montar();

    await wrapper.vm.salvar();

    expect(updateSpy).not.toHaveBeenCalled();
    expect(useAlert).not.toHaveBeenCalledWith('Distribution saved');
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('nao salva depois de falha no carregamento', async () => {
    showSpy.mockRejectedValue({ response: { status: 500 } });
    const wrapper = montar();
    await flushPromises();
    vi.mocked(useAlert).mockClear();

    await wrapper.vm.salvar();

    expect(updateSpy).not.toHaveBeenCalled();
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('nao salva sem permissao', async () => {
    showSpy.mockRejectedValue({ response: { status: 401 } });
    const wrapper = montar();
    await flushPromises();

    await wrapper.vm.salvar();

    expect(updateSpy).not.toHaveBeenCalled();
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('mostra o erro de carregamento no botao proprio', async () => {
    showSpy.mockRejectedValue({ response: { status: 500 } });
    const wrapper = montar({ embutido: false });
    await flushPromises();
    vi.mocked(useAlert).mockClear();

    await wrapper.vm.salvar();

    expect(updateSpy).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith('Could not save the distribution');
  });

  it('salva o pool carregado do servidor', async () => {
    showSpy.mockResolvedValue(resposta);
    const wrapper = montar();
    await flushPromises();

    await wrapper.vm.salvar();

    expect(updateSpy).toHaveBeenCalledWith(7, {
      ativo: true,
      modo: 'rodizio',
      pool: resposta.data.pool,
    });
    expect(useAlert).toHaveBeenCalledWith('Distribution saved');
  });
});
