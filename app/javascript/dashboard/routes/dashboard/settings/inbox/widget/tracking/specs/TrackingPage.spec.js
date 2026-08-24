import {
  config,
  enableAutoUnmount,
  flushPromises,
  mount,
} from '@vue/test-utils';
import { reactive } from 'vue';
import TrackingPage from '../TrackingPage.vue';
import { TRACKING_EVENTS } from '../../composables/widgetTrackingContract';

const inbox = reactive({
  id: 7,
  name: 'Site da Simplex',
  additional_attributes: {},
});

const dispatch = vi.fn().mockResolvedValue();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: { 'inboxes/getInbox': () => inbox, 'inboxes/getUIFlags': {} },
    dispatch,
  }),
  useMapGetter: () => ({ value: 'ltr' }),
}));

const alertas = [];
vi.mock('dashboard/composables', () => ({
  useAlert: mensagem => alertas.push(mensagem),
}));

/**
 * `axios` e global no dashboard e NAO existe no ambiente de teste. A tela le
 * duas coisas por conta propria ao montar — o log de entregas (5.14) e o estado
 * do cofre (5.02) — entao sem este duble as duas leituras morreriam num
 * `ReferenceError` engolido pelo `try`, e o teste mediria uma tela que falhou
 * por um motivo que nao e o que ele afirma.
 *
 * O default e 404: e o estado REAL desta instalacao hoje, com as rotas de 5.14
 * e 5.02 ainda nao expostas.
 */
const naoEncontrado = () => {
  // `Error` com `response` pendurado: e a forma que o axios REJEITA de verdade,
  // e e dela que o composable tira o 404 para separar "rota nao existe" de
  // "deu erro". Um objeto solto passaria no teste e mentiria sobre o contrato.
  const erro = new Error('Not Found');
  erro.response = { status: 404 };
  return Promise.reject(erro);
};
const respostaDoLog = vi.fn(naoEncontrado);
const respostaDoCofre = vi.fn(naoEncontrado);

const [i18n] = config.global.plugins;
enableAutoUnmount(afterEach);

beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.open = true;
  };
  HTMLDialogElement.prototype.close = function close() {
    this.open = false;
  };
});

beforeEach(() => {
  inbox.additional_attributes = {};
  alertas.length = 0;
  dispatch.mockClear();
  respostaDoLog.mockImplementation(naoEncontrado);
  respostaDoCofre.mockImplementation(naoEncontrado);
  // A URL importa: e dela que sai o id da conta nos dois caminhos REST.
  window.history.replaceState({}, '', '/app/accounts/3/settings/inboxes/7');
  global.axios = {
    get: url =>
      url.includes('tracking_credentials')
        ? respostaDoCofre(url)
        : respostaDoLog(url),
    post: url => respostaDoLog(url),
    put: url => respostaDoCofre(url),
  };
});
afterEach(() => {
  i18n.global.locale.value = 'en';
  document.body.innerHTML = '';
});

const build = () => {
  i18n.global.locale.value = 'pt_BR';
  return mount(TrackingPage, { props: { inboxId: 7 } });
};

const irParaAba = async (wrapper, indice) => {
  wrapper.findComponent({ name: 'TabBar' }).vm.$emit(
    // eslint-disable-next-line vue/custom-event-name-casing
    'tab-changed',
    {
      label: wrapper.vm.$t(
        [
          'INBOX_WIDGET.TRACKING.TABS.META',
          'INBOX_WIDGET.TRACKING.TABS.GOOGLE',
          'INBOX_WIDGET.TRACKING.TABS.EVENTS',
          'INBOX_WIDGET.TRACKING.TABS.DIAGNOSTICS',
        ][indice]
      ),
    }
  );
  await wrapper.vm.$nextTick();
};

describe('5.06 — as quatro sub-abas', () => {
  it('abre na Meta e alterna para as outras três', async () => {
    const wrapper = build();
    expect(wrapper.find('[data-testid="tab-meta"]').exists()).toBe(true);

    await irParaAba(wrapper, 1);
    expect(wrapper.find('[data-testid="tab-google"]').exists()).toBe(true);

    await irParaAba(wrapper, 2);
    expect(wrapper.find('[data-testid="tab-events"]').exists()).toBe(true);

    await irParaAba(wrapper, 3);
    expect(wrapper.find('[data-testid="tab-diagnostics"]').exists()).toBe(true);
  });
});

describe('5.06 — só identificador público é gravável', () => {
  it('o PATCH leva os IDs públicos e nada que pareça segredo', async () => {
    const wrapper = build();

    await wrapper
      .find('[data-testid="meta-pixel-id"] input')
      .setValue('123456789012345');
    await wrapper.find('[data-testid="save-button"]').trigger('click');
    await flushPromises();

    const [[, payload]] = dispatch.mock.calls;
    const tracking = payload.additional_attributes.widget_tracking;

    expect(tracking.meta_pixel_id).toBe('123456789012345');
    // a asserção negativa: nenhuma chave do payload casa com o padrão que o
    // servidor recusa (`/(\A|_)(token|secret)\z/i`)
    const procurarSegredo = objeto =>
      Object.entries(objeto).flatMap(([chave, valor]) => [
        ...(/(^|_)(token|secret)$/i.test(chave) ? [chave] : []),
        ...(valor && typeof valor === 'object' ? procurarSegredo(valor) : []),
      ]);
    expect(procurarSegredo(payload)).toEqual([]);
  });

  it('o campo de segredo existe, mas desabilitado e com a razão nomeando 5.02', () => {
    const wrapper = build();

    expect(wrapper.find('[data-testid="meta-token"]').exists()).toBe(true);
    expect(
      wrapper
        .find('[data-testid="meta-token"] [data-testid="secret-replace"]')
        .attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper
        .find(
          '[data-testid="meta-token"] [data-testid="secret-disabled-reason"]'
        )
        .text()
    ).toContain('5.02');
  });

  it('Pixel ID malformado reclama antes de o servidor recusar', async () => {
    const wrapper = build();

    await wrapper.find('[data-testid="meta-pixel-id"] input').setValue('abc');

    expect(wrapper.find('[data-testid="tab-meta"]').text()).toContain(
      '15 ou 16 dígitos'
    );
  });
});

describe('5.06 — o modo teste desliga sozinho', () => {
  it('ligar grava a data de início — sem ela o prazo seria só uma frase', async () => {
    const wrapper = build();

    await wrapper.find('[data-testid="test-mode"]').trigger('click');
    await wrapper.find('[data-testid="save-button"]').trigger('click');
    await flushPromises();

    const [[, payload]] = dispatch.mock.calls;
    const { test_mode: testMode } =
      payload.additional_attributes.widget_tracking;

    expect(testMode.enabled).toBe(true);
    expect(Date.parse(testMode.started_at)).not.toBeNaN();
  });

  it('ligado há mais de 7 dias aparece como expirado, e o aviso explica', () => {
    inbox.additional_attributes = {
      widget_tracking: {
        test_mode: {
          enabled: true,
          started_at: new Date(Date.now() - 8 * 864e5).toISOString(),
        },
      },
    };
    const wrapper = build();

    expect(wrapper.find('[data-testid="test-mode-expired"]').text()).toContain(
      'desligado sozinho'
    );
    expect(
      wrapper.find('[data-testid="test-mode"]').attributes('aria-checked')
    ).toBe('false');
  });
});

describe('5.06 — o mapa dos doze eventos', () => {
  it('mostra os doze, com os nomes técnicos à vista', async () => {
    const wrapper = build();
    await irParaAba(wrapper, 2);

    TRACKING_EVENTS.forEach(nome =>
      expect(wrapper.find(`[data-testid="event-${nome}"]`).exists()).toBe(true)
    );
    expect(wrapper.find('[data-testid="event-map"]').text()).toContain(
      'chatspx_lead'
    );
  });

  it('grava o mapa COMPLETO — quem consome não precisa saber os defaults', async () => {
    const wrapper = build();
    await irParaAba(wrapper, 2);

    await wrapper
      .find('[data-testid="enabled-chatspx_deal_won"]')
      .trigger('click');
    await wrapper.find('[data-testid="save-button"]').trigger('click');
    await flushPromises();

    const [[, payload]] = dispatch.mock.calls;
    const mapa = payload.additional_attributes.widget_tracking.event_map;

    expect(Object.keys(mapa)).toHaveLength(12);
    expect(mapa.chatspx_deal_won.enabled).toBe(true);
    // e o que não foi tocado vai junto, com o default de fábrica
    expect(mapa.chatspx_lead).toEqual({
      enabled: true,
      meta: 'Lead',
      ga4: 'generate_lead',
    });
  });

  it('apagar o nome no destino vira `null` — "não enviar", não string vazia', async () => {
    const wrapper = build();
    await irParaAba(wrapper, 2);

    await wrapper.find('[data-testid="meta-chatspx_lead"] input').setValue('');
    await wrapper.find('[data-testid="save-button"]').trigger('click');
    await flushPromises();

    const [[, payload]] = dispatch.mock.calls;
    expect(
      payload.additional_attributes.widget_tracking.event_map.chatspx_lead.meta
    ).toBeNull();
  });
});

describe('5.06 — o que é da conta aparece, em somente leitura', () => {
  it('mostra consentimento, interruptor, retenção e DPA', () => {
    inbox.additional_attributes = {
      widget_tracking: { consent_mode: 'advanced' },
      tracking_kill_switch: true,
      tracking_retention_days: 90,
      tracking_dpa_accepted: true,
    };
    const wrapper = build();

    expect(wrapper.find('[data-testid="account-consent"]').text()).toBe(
      'advanced'
    );
    expect(wrapper.find('[data-testid="account-retention"]').text()).toContain(
      '90'
    );
    expect(wrapper.find('[data-testid="account-dpa"]').text()).toBe('aceito');
    expect(
      wrapper.find('[data-testid="kill-switch-warning"]').text()
    ).toContain('nenhum evento sai');
  });
});

describe('5.06 — o diagnóstico não mostra valor', () => {
  it('diz que só mostra NOMES de campo, e NOMEIA a rota que falta', async () => {
    const wrapper = build();
    await flushPromises();
    await irParaAba(wrapper, 3);

    expect(
      wrapper.find('[data-testid="diagnostics-privacy"]').text()
    ).toContain('nunca os valores');
    // "vazio" sem explicacao faz o agente de suporte concluir "nao saiu
    // evento" quando a verdade e "ninguem consegue ver". A faixa diz o caminho.
    expect(
      wrapper.find('[data-testid="diagnostics-unavailable"]').text()
    ).toContain('/api/v1/accounts/3/inboxes/7/tracking_deliveries');
  });
});

describe('5.14 — o painel lê o log de verdade quando a rota existe', () => {
  const logComEntregas = {
    data: {
      retention_days: 90,
      deliveries: [
        {
          event_id: 'e1',
          name: 'chatspx_lead',
          destination: 'meta_capi',
          status: 'sent',
          http_status: 200,
          emq: 8.6,
          last_attempted_at: '14:32:10',
          field_names: ['em', 'ph', 'external_id'],
        },
        {
          event_id: 'e2',
          name: 'chatspx_lead',
          destination: 'ga4_mp',
          status: 'failed',
          http_status: 400,
          error_code: 'invalid_hash',
          error_message: 'Invalid parameter: em is not a valid hash',
          last_attempted_at: '14:32:11',
          field_names: ['em'],
        },
      ],
    },
  };

  it('mostra taxa de entrega, EMQ e retenção — as três perguntas do suporte', async () => {
    respostaDoLog.mockResolvedValue(logComEntregas);
    const wrapper = build();
    await flushPromises();
    await irParaAba(wrapper, 3);

    // uma entregue, uma falhada: 50%
    expect(wrapper.find('[data-testid="diagnostics-rate"]').text()).toBe('50%');
    expect(wrapper.find('[data-testid="diagnostics-emq"]').text()).toBe('8.6');
    expect(
      wrapper.find('[data-testid="diagnostics-retention"]').text()
    ).toContain('90');
  });

  it('agrupa o erro em vez de listar cem vezes o mesmo', async () => {
    respostaDoLog.mockResolvedValue({
      data: {
        deliveries: [
          ...Array.from({ length: 3 }, (_, i) => ({
            ...logComEntregas.data.deliveries[1],
            event_id: `x${i}`,
          })),
        ],
      },
    });
    const wrapper = build();
    await flushPromises();
    await irParaAba(wrapper, 3);

    const grupos = wrapper.findAll(
      '[data-testid="diagnostics-error-groups"] [data-testid^="error-group-"]'
    );
    expect(grupos).toHaveLength(1);
    expect(grupos[0].text()).toContain('3×');
  });

  it('o botão de teste devolve o status HTTP REAL, não um "enviado com sucesso"', async () => {
    respostaDoLog.mockResolvedValueOnce({ data: { deliveries: [] } });
    const wrapper = build();
    await flushPromises();
    await irParaAba(wrapper, 3);

    respostaDoLog.mockResolvedValueOnce({
      data: {
        delivery: {
          event_id: 'teste',
          name: 'chatspx_lead',
          destination: 'meta_capi',
          status: 'failed',
          http_status: 400,
          error_message: 'Invalid access token',
          field_names: ['em'],
        },
      },
    });
    await wrapper
      .find('[data-testid="diagnostics-send-test"]')
      .trigger('click');
    await flushPromises();

    const retorno = wrapper.find('[data-testid="diagnostics-test-result"]');
    expect(retorno.text()).toContain('400');
    expect(retorno.text()).toContain('failed');
  });
});

describe('5.14 — o interruptor desta caixa', () => {
  /**
   * O controle EXISTE na tela e NAO grava — de proposito, e o teste cobra as
   * duas metades. `kill_switch` so vale se chegar ao widget, e quem decide isso
   * e a lista branca do bloco 5.01, onde a chave ainda nao esta. Um botao que
   * mudasse de estado e nao desligasse nada faria o administrador acreditar que
   * parou o rastreio no meio de um incidente.
   */
  it('declara o que o interruptor faz e diz que ainda não está disponível', async () => {
    const wrapper = build();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="inbox-kill-switch-card"]').text()
    ).toContain('Desligar o rastreio desta caixa');
    expect(
      wrapper.find('[data-testid="kill-switch-blocked"]').text()
    ).toContain('5.01');
  });

  it('NÃO existe controle que grave `kill_switch` — nada é enviado por engano', async () => {
    const wrapper = build();
    await flushPromises();

    expect(wrapper.find('[data-testid="inbox-kill-switch"]').exists()).toBe(
      false
    );
    // e o rascunho continua sem a chave: o `permit` do servidor a recusaria
    await wrapper
      .find('[data-testid="meta-pixel-id"] input')
      .setValue('123456789012345');
    await wrapper.find('[data-testid="save-button"]').trigger('click');
    await flushPromises();

    const [[, payload]] = dispatch.mock.calls;
    expect(payload.additional_attributes.widget_tracking).not.toHaveProperty(
      'kill_switch'
    );
  });

  it('com o interruptor da CONTA acionado, a tela diz que nada sai desta caixa', async () => {
    inbox.additional_attributes = { tracking_kill_switch: true };
    const wrapper = build();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="kill-switch-account-wins"]').text()
    ).toContain('nenhum evento sai');
  });
});

describe('5.06 — o campo de segredo consome o contrato do 5.02', () => {
  it('sem o cofre no ar, fica desabilitado e nomeia o bloco', async () => {
    const wrapper = build();
    await flushPromises();

    expect(
      wrapper
        .find('[data-testid="meta-token"] [data-testid="secret-replace"]')
        .attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper
        .find(
          '[data-testid="meta-token"] [data-testid="secret-disabled-reason"]'
        )
        .text()
    ).toContain('5.02');
  });

  it('com o cofre no ar, mostra `configured` + os 4 últimos — e nunca o valor', async () => {
    respostaDoCofre.mockResolvedValue({
      data: {
        credentials: {
          meta_access_token: { configured: true, last_four: '9f2a' },
          ga4_api_secret: { configured: false, last_four: '' },
        },
      },
    });
    const wrapper = build();
    await flushPromises();

    expect(
      wrapper
        .find('[data-testid="meta-token"] [data-testid="secret-mask"]')
        .text()
    ).toBe('••••••••9f2a');
    // o botao volta a funcionar: o cofre existe
    expect(
      wrapper
        .find('[data-testid="meta-token"] [data-testid="secret-replace"]')
        .attributes('disabled')
    ).toBeUndefined();
  });

  it('o segredo NÃO viaja no PATCH da inbox — vai por rota própria', async () => {
    respostaDoCofre.mockResolvedValue({
      data: {
        credentials: {
          meta_access_token: { configured: false, last_four: '' },
          ga4_api_secret: { configured: false, last_four: '' },
        },
      },
    });
    const wrapper = build();
    await flushPromises();

    await wrapper
      .find('[data-testid="meta-token"] [data-testid="secret-replace"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="meta-token"] [data-testid="secret-input"] input')
      .setValue('EAAG-token-novo');
    await wrapper
      .find('[data-testid="meta-token"] [data-testid="secret-confirm"]')
      .trigger('click');
    await flushPromises();

    // foi pelo PUT do cofre...
    expect(respostaDoCofre).toHaveBeenCalledWith(
      '/api/v1/accounts/3/inboxes/7/tracking_credentials/meta_access_token'
    );
    // ...e o PATCH da inbox nem aconteceu: nada mudou no rascunho
    expect(dispatch).not.toHaveBeenCalled();
  });
});
