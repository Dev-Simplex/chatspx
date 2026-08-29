import { mount, flushPromises } from '@vue/test-utils';
import PartialLeadReports from '../PartialLeadReports.vue';

/**
 * Bloco 4.18 — "quantos leads perdemos e onde", agora com tela.
 *
 * O dublê devolve a forma REAL de `Widget::PartialLeads::Report#perform` (as seis chaves,
 * com `by_step` indexado por número e `by_step_name` por nome de campo). Dublê com forma
 * inventada mediria a si mesmo.
 */
const { apiSpy } = vi.hoisted(() => ({ apiSpy: vi.fn() }));

vi.mock('dashboard/api/reports', () => ({
  default: { getPartialLeads: apiSpy },
}));

const RELATORIO = {
  started: 4,
  completed: 1,
  abandoned: 3,
  completion_rate: 0.25,
  by_step: { 1: 1, 3: 2 },
  by_step_name: { phoneNumber: 2, fullName: 1 },
};

/* eslint-disable vue/custom-event-name-casing -- o nome do evento e do componente REAL
   (`ReportFilters` emite `filter-change`, em kebab-case, e `PartialLeadReports` escuta esse
   nome). Renomear aqui faria o duble medir um contrato que nao existe. */
const ReportFiltersStub = {
  name: 'ReportFilters',
  emits: ['filter-change'],
  // O filtro real emite `filter-change` no `mounted`; o dublê faz o mesmo para que a tela
  // seja exercida pelo caminho por onde ela é exercida de verdade.
  mounted() {
    this.$emit('filter-change', { from: 1000, to: 2000 });
  },
  template: '<div data-testid="filters" />',
};
/* eslint-enable vue/custom-event-name-casing */

const montar = async () => {
  const wrapper = mount(PartialLeadReports, {
    global: {
      stubs: {
        ReportHeader: true,
        ReportFilters: ReportFiltersStub,
        Spinner: true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const texto = (wrapper, testid) =>
  wrapper.find(`[data-testid="${testid}"]`).text();

describe('PartialLeadReports (4.18)', () => {
  it('pede o relatório ao endpoint do bloco, com a janela do filtro', async () => {
    apiSpy.mockResolvedValue({ data: RELATORIO });
    await montar();

    expect(apiSpy).toHaveBeenCalledWith({ from: 1000, to: 2000 });
  });

  it('responde QUANTOS: iniciados, concluídos e perdidos', async () => {
    apiSpy.mockResolvedValue({ data: RELATORIO });
    const wrapper = await montar();

    expect(texto(wrapper, 'partial-lead-started')).toContain('4');
    expect(texto(wrapper, 'partial-lead-completed')).toContain('1');
    expect(texto(wrapper, 'partial-lead-completed')).toContain('25%');
    expect(texto(wrapper, 'partial-lead-abandoned')).toContain('3');
    expect(texto(wrapper, 'partial-lead-abandoned')).toContain('75%');
  });

  it('responde ONDE: o campo em que a pessoa parou, do pior para o melhor', async () => {
    // É a metade que serve para consertar alguma coisa. "60% desistem" não diz o que mexer;
    // "45% param no telefone" diz.
    apiSpy.mockResolvedValue({ data: RELATORIO });
    const wrapper = await montar();

    const linhas = wrapper
      .findAll('[data-testid="partial-lead-steps"] tbody tr')
      .map(linha => linha.text());

    expect(linhas).toHaveLength(2);
    expect(linhas[0]).toContain('phoneNumber');
    expect(linhas[0]).toContain('2');
    expect(linhas[0]).toContain('66.7%');
    expect(linhas[1]).toContain('fullName');
  });

  it('sem nome de campo gravado, cai no NÚMERO da etapa em vez de sumir', async () => {
    // Sumir seria dizer "ninguém parou aqui" — a linha existe, o nome é que não foi gravado.
    apiSpy.mockResolvedValue({ data: { ...RELATORIO, by_step_name: {} } });
    const wrapper = await montar();

    const linhas = wrapper
      .findAll('[data-testid="partial-lead-steps"] tbody tr')
      .map(linha => linha.text());

    expect(linhas).toHaveLength(2);
    expect(linhas[0]).toContain('Step 3');
  });

  it('período sem ninguém diz "ninguém começou", e não 0% de abandono', async () => {
    // 0% de abandono num período vazio lê-se como sucesso. É a mesma classe de mentira do
    // "origem direta" que o 1.22 recusa.
    apiSpy.mockResolvedValue({
      data: {
        started: 0,
        completed: 0,
        abandoned: 0,
        completion_rate: 0.0,
        by_step: {},
        by_step_name: {},
      },
    });
    const wrapper = await montar();

    expect(wrapper.find('[data-testid="partial-lead-empty"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="partial-lead-abandoned"]').exists()
    ).toBe(false);
  });

  it('endpoint fora do ar mostra erro, e não um relatório de zeros', async () => {
    apiSpy.mockRejectedValue(new Error('500'));
    const wrapper = await montar();

    expect(wrapper.find('[data-testid="partial-lead-error"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="partial-lead-started"]').exists()).toBe(
      false
    );
  });
});
