import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/teamsSettings.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/teamsSettings.json';
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

describe.each([
  ['pt_BR', ptBR, 'nada é repassado e ninguém é avisado'],
  ['en', en, 'nothing is reassigned and no one is notified'],
])('TeamDistribuicaoFields textos e repasse (%s)', (locale, messages, help) => {
  const textos = messages.TEAMS_SETTINGS.DISTRIBUICAO;
  const traduzir = key =>
    key.split('.').reduce((value, part) => value[part], messages);
  const montarTraduzido = () =>
    mount(TeamDistribuicaoFields, {
      props: { teamId: 7, embutido: true },
      global: {
        mocks: { $t: traduzir },
        stubs: { Spinner: true, NextButton: true },
      },
    });

  beforeEach(() => {
    showSpy.mockReset().mockResolvedValue({
      data: {
        ...resposta.data,
        politica: {
          ativo: true,
          modo: 'rodizio',
          repasse_automatico: true,
          max_repasses: 3,
          pool_esgotado_destino_user_id: 9,
        },
      },
    });
    updateSpy
      .mockReset()
      .mockImplementation((id, payload) =>
        Promise.resolve({ data: { ...resposta.data, politica: payload } })
      );
  });

  it('nao promete avisar gerente na tela nem no erro de permissao', async () => {
    const wrapper = montarTraduzido();
    await flushPromises();
    expect(wrapper.text()).not.toMatch(/gerente|manager/i);
    wrapper.unmount();

    showSpy.mockRejectedValue({ response: { status: 401 } });
    const forbidden = montarTraduzido();
    await flushPromises();
    expect(forbidden.text()).toContain(textos.FORBIDDEN);
    expect(forbidden.text()).not.toMatch(/gerente|manager/i);
  });

  it('permite desligar e religar, mantendo booleanos no payload e campos dependentes', async () => {
    const wrapper = montarTraduzido();
    await flushPromises();
    const label = wrapper
      .findAll('label')
      .find(item => item.text().includes(textos.SLA.REPASSE));
    const controle = label.get('input[type="checkbox"]');
    expect(controle.element.checked).toBe(true);
    expect(wrapper.text()).toContain(textos.SLA.MAX);
    expect(wrapper.text()).toContain(textos.SLA.DESTINO);
    expect(wrapper.text()).not.toContain(help);

    await controle.setValue(false);
    expect(wrapper.text()).toContain(help);
    expect(wrapper.text()).not.toContain(textos.SLA.MAX);
    expect(wrapper.text()).not.toContain(textos.SLA.DESTINO);
    await wrapper.vm.salvar();
    expect(updateSpy).toHaveBeenLastCalledWith(
      7,
      expect.objectContaining({
        repasse_automatico: false,
        max_repasses: 3,
        pool_esgotado_destino_user_id: 9,
      })
    );

    await controle.setValue(true);
    expect(wrapper.text()).not.toContain(help);
    expect(wrapper.text()).toContain(textos.SLA.MAX);
    expect(wrapper.text()).toContain(textos.SLA.DESTINO);
    await wrapper.vm.salvar();
    expect(updateSpy).toHaveBeenLastCalledWith(
      7,
      expect.objectContaining({ repasse_automatico: true })
    );
  });
});
