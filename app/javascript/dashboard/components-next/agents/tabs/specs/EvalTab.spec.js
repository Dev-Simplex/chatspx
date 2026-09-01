import { mount, flushPromises } from '@vue/test-utils';
import EvalTab from '../EvalTab.vue';
import EvalAPI from 'dashboard/api/captain/eval';

// 6.02 — a tela do eval. A API é dublada: nenhum destes testes fala com servidor,
// e muito menos com IA.
vi.mock('dashboard/api/captain/eval', () => ({
  default: {
    getCases: vi.fn(),
    getRuns: vi.fn(),
    estimate: vi.fn(),
    createCase: vi.fn(),
    deleteCase: vi.fn(),
    run: vi.fn(),
    getRun: vi.fn(),
    compare: vi.fn(),
  },
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { assistantId: '7', accountId: '1' } }),
}));

const t = (key, params = {}) =>
  Object.keys(params).length
    ? `${key}(${Object.values(params).join(',')})`
    : key;

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

const estimativa = {
  casos: 2,
  respostas: 2,
  tokens_estimados: 1234,
  base_da_estimativa: '4 caracteres por token',
  saldo: { disponivel: 10, total: 100, consumido: 90 },
  excede_saldo: false,
};

const casos = [
  {
    id: 1,
    titulo: 'diz o horário',
    mensagens: [{ role: 'user', content: 'que horas abre?' }],
    expectativas: {},
  },
];

const execucoes = [
  {
    id: 9,
    status: 'concluida',
    casos_ok: 1,
    casos_total: 2,
    aprovacao: 50,
    prompt_fingerprint: 'abc123',
  },
  {
    id: 8,
    status: 'concluida',
    casos_ok: 2,
    casos_total: 2,
    aprovacao: 100,
    prompt_fingerprint: 'zzz999',
  },
];

const mountTab = (overrides = {}) => {
  EvalAPI.getCases.mockResolvedValue({
    data: { data: overrides.casos ?? casos },
  });
  EvalAPI.getRuns.mockResolvedValue({
    data: { data: overrides.runs ?? execucoes },
  });
  EvalAPI.estimate.mockResolvedValue({
    data: { data: overrides.estimate ?? estimativa },
  });
  return mount(EvalTab, {
    global: { stubs: { AiEmptyState: true, AiSelect: true, AiButton: false } },
  });
};

beforeEach(() => vi.clearAllMocks());

describe('EvalTab', () => {
  it('shows the cost BEFORE anything runs — e não dispara execução para isso', async () => {
    const wrapper = mountTab();
    await flushPromises();

    expect(EvalAPI.estimate).toHaveBeenCalledWith(7);
    expect(EvalAPI.run).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="eval-cost"]').text()).toContain('2');
    expect(wrapper.find('[data-testid="eval-cost"]').text()).toContain('1234');
  });

  it('warns when the run would not fit in the balance', async () => {
    const wrapper = mountTab({
      estimate: { ...estimativa, excede_saldo: true, saldo: { disponivel: 1 } },
    });
    await flushPromises();

    expect(wrapper.find('[data-testid="eval-cost-warning"]').exists()).toBe(
      true
    );
  });

  it('only runs the set when the button is pressed', async () => {
    EvalAPI.run.mockResolvedValue({
      data: { data: { id: 10, status: 'pendente' } },
    });
    const wrapper = mountTab();
    await flushPromises();

    await wrapper.find('[data-testid="eval-run"]').trigger('click');
    await flushPromises();

    expect(EvalAPI.run).toHaveBeenCalledWith(7);
  });

  it('does not offer the run when there is no case to run', async () => {
    const wrapper = mountTab({ casos: [] });
    await flushPromises();

    expect(
      wrapper.find('[data-testid="eval-run"]').attributes('disabled')
    ).toBeDefined();
  });

  it('shows the verdict per case, with the reason of what failed', async () => {
    EvalAPI.getRun.mockResolvedValue({
      data: {
        data: {
          id: 9,
          resultados: [
            {
              eval_case_id: 1,
              titulo: 'diz o horário',
              passou: false,
              resposta: 'abrimos cedo',
              findings: [{ porque: 'a resposta não contém "das 9h"' }],
            },
            {
              eval_case_id: 2,
              titulo: 'não promete desconto',
              passou: true,
              resposta: 'sem desconto',
              findings: [],
            },
          ],
        },
      },
    });
    const wrapper = mountTab();
    await flushPromises();

    await wrapper
      .findAll('button')
      .find(b => b.text() === 'CAPTAIN.AGENT_TABS.EVAL.OPEN_RUN')
      .trigger('click');
    await flushPromises();

    const detalhe = wrapper.find('[data-testid="eval-detail"]');
    expect(detalhe.text()).toContain('a resposta não contém "das 9h"');
    expect(detalhe.text()).toContain('CAPTAIN.AGENT_TABS.EVAL.PASSED');
    expect(detalhe.text()).toContain('CAPTAIN.AGENT_TABS.EVAL.FAILED');
  });

  it('answers "quantos regrediram" when two runs are compared', async () => {
    EvalAPI.compare.mockResolvedValue({
      data: {
        data: {
          mesmo_prompt: false,
          regrediram: [{ eval_case_id: 1, titulo: 'diz o horário' }],
          corrigiram: [],
          casos: [
            { eval_case_id: 1, titulo: 'diz o horário', situacao: 'regrediu' },
          ],
        },
      },
    });
    const wrapper = mountTab();
    await flushPromises();

    wrapper.vm.baseRunId = '8';
    wrapper.vm.comparedRunId = '9';
    await wrapper.vm.$nextTick();
    await wrapper.find('[data-testid="eval-compare"]').trigger('click');
    await flushPromises();

    expect(EvalAPI.compare).toHaveBeenCalledWith(7, '8', '9');
    expect(wrapper.find('[data-testid="eval-comparison"]').text()).toContain(
      'CAPTAIN.AGENT_TABS.EVAL.REGRESSED(1)'
    );
  });

  it('refuses to compare a run with itself', async () => {
    const wrapper = mountTab();
    await flushPromises();

    wrapper.vm.baseRunId = '9';
    wrapper.vm.comparedRunId = '9';
    await wrapper.vm.$nextTick();

    expect(
      wrapper.find('[data-testid="eval-compare"]').attributes('disabled')
    ).toBeDefined();
  });

  // ── O STATUS NA TELA ────────────────────────────────────────────────────────────
  // A execução sai da API PENDENTE e quem roda é um job. Antes, a tela pegava o
  // status uma vez no mount e nunca mais: ficava em "pendente" para sempre, e só um
  // F5 revelava o resultado.
  describe('o acompanhamento do status', () => {
    // `clearAllMocks` não esvazia a fila de `mockResolvedValueOnce`, e uma fila
    // vazada de um teste para o outro faz o vizinho passar por engano.
    beforeEach(() => {
      EvalAPI.getRuns.mockReset();
      EvalAPI.estimate.mockReset();
      vi.useFakeTimers();
    });
    afterEach(() => vi.useRealTimers());

    const emVoo = [
      { ...execucoes[0], id: 11, status: 'pendente', casos_ok: 0 },
    ];
    const terminada = [{ ...execucoes[0], id: 11, status: 'concluida' }];

    it('follows a run that is still going, until it settles', async () => {
      // 1ª e 2ª leitura: ainda em voo. Da 3ª em diante: terminada (o default do mountTab).
      EvalAPI.getRuns.mockResolvedValueOnce({ data: { data: emVoo } });
      EvalAPI.getRuns.mockResolvedValueOnce({ data: { data: emVoo } });
      const wrapper = mountTab({ runs: terminada });
      await flushPromises();

      expect(EvalAPI.getRuns).toHaveBeenCalledTimes(1);
      expect(wrapper.find('[data-testid="eval-run-status"]').text()).toContain(
        'CAPTAIN.AGENT_TABS.EVAL.STATUS.PENDENTE'
      );

      await vi.advanceTimersByTimeAsync(3000);
      expect(EvalAPI.getRuns).toHaveBeenCalledTimes(2);
      expect(wrapper.find('[data-testid="eval-run-status"]').text()).toContain(
        'CAPTAIN.AGENT_TABS.EVAL.STATUS.PENDENTE'
      );

      await vi.advanceTimersByTimeAsync(3000);
      await flushPromises();
      expect(EvalAPI.getRuns).toHaveBeenCalledTimes(3);
      expect(wrapper.find('[data-testid="eval-run-status"]').text()).toContain(
        'CAPTAIN.AGENT_TABS.EVAL.STATUS.CONCLUIDA'
      );

      // Terminou: para de perguntar.
      await vi.advanceTimersByTimeAsync(30000);
      expect(EvalAPI.getRuns).toHaveBeenCalledTimes(3);
    });

    it('never polls when nothing is in flight', async () => {
      mountTab({ runs: terminada });
      await flushPromises();

      await vi.advanceTimersByTimeAsync(60000);

      expect(EvalAPI.getRuns).toHaveBeenCalledTimes(1);
    });

    it('re-reads the balance when the run settles — a execução debitou respostas', async () => {
      EvalAPI.getRuns.mockResolvedValueOnce({ data: { data: emVoo } });
      mountTab({ runs: terminada });
      await flushPromises();

      expect(EvalAPI.estimate).toHaveBeenCalledTimes(1);

      await vi.advanceTimersByTimeAsync(3000);
      await flushPromises();

      expect(EvalAPI.estimate).toHaveBeenCalledTimes(2);
    });

    it('says the status in words — não o enum cru do servidor', async () => {
      const wrapper = mountTab({ runs: emVoo });
      await flushPromises();

      const linha = wrapper.find('[data-testid="eval-run-status"]').text();
      expect(linha).not.toContain('pendente');
      expect(wrapper.find('[data-testid="eval-following"]').exists()).toBe(
        true
      );
    });

    it('does not offer a second run while one is still in flight', async () => {
      const wrapper = mountTab({ runs: emVoo });
      await flushPromises();

      expect(
        wrapper.find('[data-testid="eval-run"]').attributes('disabled')
      ).toBeDefined();
    });

    it('stops polling when the tab goes away', async () => {
      const wrapper = mountTab({ runs: emVoo });
      await flushPromises();

      wrapper.unmount();
      await vi.advanceTimersByTimeAsync(30000);

      expect(EvalAPI.getRuns).toHaveBeenCalledTimes(1);
    });

    it('keeps the screen quiet when the poll request fails', async () => {
      mountTab({ runs: emVoo });
      await flushPromises();
      EvalAPI.getRuns.mockRejectedValue(new Error('rede caiu'));

      await vi.advanceTimersByTimeAsync(3000);
      await flushPromises();

      expect(EvalAPI.getRuns).toHaveBeenCalledTimes(2);
      // Desistiu de acompanhar em vez de martelar o servidor caído.
      await vi.advanceTimersByTimeAsync(30000);
      expect(EvalAPI.getRuns).toHaveBeenCalledTimes(2);
    });
  });

  // Rótulo com emoji dentro da string vira nome acessível ruim. Todo controle sem
  // texto visível desta tela nasce com aria-label de texto limpo.
  it('gives every control an accessible name, and none of them carries a symbol', async () => {
    const wrapper = mountTab();
    await flushPromises();

    const pictografico = /\p{Extended_Pictographic}/u;
    const controles = wrapper.findAll('button');
    expect(controles.length).toBeGreaterThan(0);
    controles.forEach(botao => {
      const nome = botao.attributes('aria-label') || botao.text();
      expect(nome.trim()).not.toBe('');
      expect(pictografico.test(nome)).toBe(false);
    });
  });
});
