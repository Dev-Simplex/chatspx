import { shallowMount, flushPromises } from '@vue/test-utils';
import ConversationOriginReports from '../ConversationOriginReports.vue';
import OriginDimensionTable from '../components/OriginDimensionTable.vue';
import ReportsAPI from 'dashboard/api/reports';

// Bloco 1.22 — a tela nao pode mentir em dois pontos:
//   1. conversa sem origem = "origem nao disponivel", NUNCA "origem direta";
//   2. periodo anterior a medicao = rotulado e contado, NUNCA vazio nem zerado.
vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/api/reports', () => ({
  default: { getConversationOrigin: vi.fn() },
}));

const $t = (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key);

const montar = async data => {
  ReportsAPI.getConversationOrigin.mockResolvedValue({ data });
  const wrapper = shallowMount(ConversationOriginReports, {
    global: {
      mocks: { $t },
      stubs: { ReportHeader: true, ReportFilters: true, Spinner: true },
    },
  });
  await wrapper
    .findComponent({ name: 'ReportFilters' })
    .vm.$emit('filterChange', { from: 1000, to: 2000 });
  await flushPromises();
  return wrapper;
};

const RELATORIO_COM_MEDICAO = {
  measurement_started_at: '2026-08-10T00:00:00.000Z',
  before_measurement: { conversations_count: 12, covers_whole_range: false },
  measured: {
    conversations_count: 4,
    source: [
      { value: 'google', count: 3 },
      { value: null, count: 1 },
    ],
    medium: [{ value: 'cpc', count: 3 }],
    campaign: [{ value: 'verao', count: 3 }],
    origin_kind: [
      { value: 'busca_paga', count: 3 },
      { value: 'ia_generativa', count: 1 },
    ],
  },
};

describe('OriginDimensionTable', () => {
  const montarTabela = rows =>
    shallowMount(OriginDimensionTable, {
      props: { title: 'Por origem', rows, testid: 'origin-source' },
      global: { mocks: { $t } },
    });

  it('rotula a linha sem origem como "origem nao disponivel", e nunca como "direta"', () => {
    const wrapper = montarTabela([
      { value: 'google', count: 3 },
      { value: null, count: 1 },
    ]);
    const linhas = wrapper.findAll('tbody tr');

    expect(linhas).toHaveLength(2);
    expect(linhas[0].text()).toContain('google');
    expect(linhas[1].text()).toContain('ORIGIN_REPORTS.UNAVAILABLE');
    expect(wrapper.text()).not.toContain('direta');
    expect(wrapper.text()).not.toContain('direct');
  });

  it('calcula a participacao de cada linha sobre o total da dimensao', () => {
    const linhas = montarTabela([
      { value: 'google', count: 3 },
      { value: null, count: 1 },
    ]).findAll('tbody tr');

    expect(linhas[0].text()).toContain('75%');
    expect(linhas[1].text()).toContain('25%');
  });

  it('nao divide por zero quando a dimensao esta vazia', () => {
    expect(montarTabela([]).findAll('tbody tr')).toHaveLength(0);
  });

  // Defeito pego na validacao em navegador: sem `valueLabels`, a dimensao "tipo de origem"
  // mostrava `busca_paga` e `nao_disponivel` — valor de MAQUINA na cara do cliente.
  it('traduz valor de vocabulario fechado quando recebe o mapa de rotulos', () => {
    const wrapper = shallowMount(OriginDimensionTable, {
      props: {
        title: 'Por tipo de origem',
        testid: 'origin-origin_kind',
        rows: [
          { value: 'busca_paga', count: 6 },
          { value: 'nao_disponivel', count: 4 },
        ],
        valueLabels: {
          busca_paga: 'Busca paga',
          nao_disponivel: 'origem nao disponivel',
        },
      },
      global: { mocks: { $t } },
    });
    const linhas = wrapper.findAll('tbody tr');

    expect(linhas[0].text()).toContain('Busca paga');
    expect(linhas[1].text()).toContain('origem nao disponivel');
    expect(wrapper.text()).not.toContain('busca_paga');
    expect(wrapper.text()).not.toContain('nao_disponivel');
  });

  it('sem mapa de rotulos, o valor do cliente sai como ele escreveu', () => {
    const linhas = montarTabela([
      { value: 'institucional_agosto', count: 2 },
    ]).findAll('tbody tr');

    expect(linhas[0].text()).toContain('institucional_agosto');
  });
});

describe('ConversationOriginReports', () => {
  it('mostra o periodo anterior a medicao com a contagem, nunca vazio', async () => {
    const wrapper = await montar(RELATORIO_COM_MEDICAO);
    const faixa = wrapper.find('[data-testid="before-measurement"]');

    expect(faixa.exists()).toBe(true);
    expect(faixa.text()).toContain('ORIGIN_REPORTS.BEFORE_MEASUREMENT.TITLE');
    expect(faixa.text()).toContain('"count":12');
  });

  it('quando a conta nunca foi medida, o periodo inteiro e "antes da medicao" e nada aparece zerado', async () => {
    const wrapper = await montar({
      measurement_started_at: null,
      before_measurement: { conversations_count: 7, covers_whole_range: true },
      measured: {
        conversations_count: 0,
        source: [],
        medium: [],
        campaign: [],
        origin_kind: [],
      },
    });

    const faixa = wrapper.find('[data-testid="before-measurement"]');
    expect(faixa.exists()).toBe(true);
    expect(faixa.text()).toContain(
      'ORIGIN_REPORTS.BEFORE_MEASUREMENT.WHOLE_RANGE'
    );
    expect(faixa.text()).toContain('"count":7');
    // sem tabela de zeros: uma tabela vazia seria lida como "ninguem veio"
    expect(wrapper.findAllComponents(OriginDimensionTable)).toHaveLength(0);
    expect(
      wrapper.find('[data-testid="no-measured-conversations"]').exists()
    ).toBe(false);
  });

  it('entrega as 4 dimensoes com as linhas que vieram da API', async () => {
    const wrapper = await montar(RELATORIO_COM_MEDICAO);
    const tabelas = wrapper.findAllComponents(OriginDimensionTable);

    expect(tabelas.map(tabela => tabela.props('testid'))).toEqual([
      'origin-source',
      'origin-medium',
      'origin-campaign',
      'origin-origin_kind',
    ]);
    expect(tabelas[0].props('rows')).toEqual(
      RELATORIO_COM_MEDICAO.measured.source
    );
    expect(tabelas[3].props('rows')).toEqual(
      RELATORIO_COM_MEDICAO.measured.origin_kind
    );
  });

  it('erro da API nao deixa a tela mostrando dado velho como se fosse novo', async () => {
    ReportsAPI.getConversationOrigin.mockRejectedValue(new Error('boom'));
    const wrapper = shallowMount(ConversationOriginReports, {
      global: {
        mocks: { $t },
        stubs: { ReportHeader: true, ReportFilters: true, Spinner: true },
      },
    });
    await wrapper
      .findComponent({ name: 'ReportFilters' })
      .vm.$emit('filterChange', { from: 1, to: 2 });
    await flushPromises();

    expect(wrapper.text()).toContain('ORIGIN_REPORTS.ERROR');
    expect(wrapper.findAllComponents(OriginDimensionTable)).toHaveLength(0);
  });
});
