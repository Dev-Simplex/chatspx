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
  it('diz que só mostra NOMES de campo, e explica por que está vazio', async () => {
    const wrapper = build();
    await irParaAba(wrapper, 3);

    expect(
      wrapper.find('[data-testid="diagnostics-privacy"]').text()
    ).toContain('nunca os valores');
    expect(
      wrapper.find('[data-testid="diagnostics-unavailable"]').text()
    ).toContain('5.14');
  });
});
