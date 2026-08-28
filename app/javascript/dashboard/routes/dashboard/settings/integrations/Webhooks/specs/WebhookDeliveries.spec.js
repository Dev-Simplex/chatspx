import { flushPromises, mount } from '@vue/test-utils';
import WebhookDeliveries from '../WebhookDeliveries.vue';
import WebhooksAPI from 'dashboard/api/webhooks';

/**
 * Bloco 4.14 — a tela de entregas.
 *
 * O ACEITE tem duas metades e as duas sao medidas aqui: a tela MOSTRA a entrega falhada
 * (com o motivo, nao so um status colorido) e o reenvio sai com o MESMO delivery id.
 *
 * O dublê é do módulo `dashboard/api/webhooks` — o mesmo especificador que o componente
 * importa. Trocar o import sem trocar esta linha deixaria o mock órfão, e um mock órfão
 * passa verde em silêncio.
 */
vi.mock('dashboard/api/webhooks', () => ({
  default: {
    deliveries: vi.fn(),
    replay: vi.fn(),
    rotateSecret: vi.fn(),
  },
}));

const alertas = [];
vi.mock('dashboard/composables', () => ({
  useAlert: mensagem => alertas.push(mensagem),
}));

/** O SEGREDO do webhook. Ele entra de propósito: sem ele a busca mediria zero. */
const SEGREDO = 'wh_sec_9f3c1a77b2e64d0a8c5b1e2f3a4d5c6e';

const webhook = {
  id: 7,
  url: 'https://destino.exemplo.com/h',
  secret: SEGREDO,
  has_secret: true,
};

const ENTREGA_FALHADA = {
  id: 42,
  delivery_id: 'entrega-42',
  event: 'conversation_created',
  status: 'failed',
  http_status: 500,
  attempts: 3,
  error_message: '500 Internal Server Error',
  delivered_at: null,
  created_at: '2026-08-20T10:00:00.000Z',
};

const ENTREGA_OK = {
  id: 43,
  delivery_id: 'entrega-43',
  event: 'message_created',
  status: 'delivered',
  http_status: 200,
  attempts: 1,
  error_message: null,
  delivered_at: '2026-08-20T11:00:00.000Z',
  created_at: '2026-08-20T11:00:00.000Z',
};

const montar = async (deliveries = [ENTREGA_FALHADA]) => {
  WebhooksAPI.deliveries.mockResolvedValue({
    data: { payload: { deliveries } },
  });
  const wrapper = mount(WebhookDeliveries, {
    props: { webhook, onClose: () => {} },
    global: {
      stubs: {
        // O stub global de `NextButton` engole o `label`; aqui ele precisa aparecer,
        // senão não dá para distinguir "Reenviar" de "Atualizar" e de "Fechar".
        NextButton: {
          props: ['label', 'isLoading', 'disabled'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

beforeEach(() => {
  alertas.length = 0;
  vi.clearAllMocks();
});

describe('4.14 — a tela mostra a entrega falhada', () => {
  it('desenha o status, o codigo HTTP e o MOTIVO', async () => {
    const wrapper = await montar();
    const texto = wrapper.text();

    expect(texto).toContain('failed');
    expect(texto).toContain('500');
    expect(texto).toContain('500 Internal Server Error');
    expect(texto).toContain('conversation_created');
    expect(texto).toContain('entrega-42');
  });

  it('busca o log da inbox certa', async () => {
    await montar();

    expect(WebhooksAPI.deliveries).toHaveBeenCalledWith(7);
  });

  it('so oferece reenvio para o que FALHOU', async () => {
    const wrapper = await montar([ENTREGA_FALHADA, ENTREGA_OK]);
    const reenviar = wrapper
      .findAll('button')
      .filter(b => b.text() === 'Resend');

    // duas linhas na tela, um unico botao de reenvio
    expect(wrapper.findAll('tbody tr')).toHaveLength(2);
    expect(reenviar).toHaveLength(1);
  });

  it('lista vazia diz que nao ha entregas, em vez de tabela em branco', async () => {
    const wrapper = await montar([]);

    expect(wrapper.text()).toContain('No deliveries recorded yet');
    expect(wrapper.find('tbody').exists()).toBe(false);
  });

  it('erro de carga aparece na tela em vez de virar lista vazia', async () => {
    WebhooksAPI.deliveries.mockRejectedValue({
      response: { data: { message: 'Boom' } },
    });
    const wrapper = mount(WebhookDeliveries, {
      props: { webhook, onClose: () => {} },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('Boom');
  });
});

describe('4.14 — o reenvio chega com o MESMO delivery id', () => {
  it('manda a chave da LINHA e anuncia o id que voltou do servidor', async () => {
    WebhooksAPI.replay.mockResolvedValue({
      data: { delivery_id: 'entrega-42', attempts: 4 },
    });
    const wrapper = await montar();

    await wrapper
      .findAll('button')
      .filter(b => b.text() === 'Resend')[0]
      .trigger('click');
    await flushPromises();

    // o que o front manda e a chave primaria da linha (42), nao o delivery_id
    expect(WebhooksAPI.replay).toHaveBeenCalledWith(7, 42);
    // e o que ele ANUNCIA e o id que o destino vai usar para deduplicar
    expect(alertas[0]).toContain('entrega-42');
  });

  it('recarrega o log depois do reenvio — a tentativa nova precisa aparecer', async () => {
    WebhooksAPI.replay.mockResolvedValue({
      data: { delivery_id: 'entrega-42' },
    });
    const wrapper = await montar();
    expect(WebhooksAPI.deliveries).toHaveBeenCalledTimes(1);

    await wrapper
      .findAll('button')
      .filter(b => b.text() === 'Resend')[0]
      .trigger('click');
    await flushPromises();

    expect(WebhooksAPI.deliveries).toHaveBeenCalledTimes(2);
  });

  it('falha no reenvio vira aviso, nao excecao silenciosa', async () => {
    WebhooksAPI.replay.mockRejectedValue(new Error('nao foi'));
    const wrapper = await montar();

    await wrapper
      .findAll('button')
      .filter(b => b.text() === 'Resend')[0]
      .trigger('click');
    await flushPromises();

    expect(alertas[0]).toContain('Could not resend');
  });
});

describe('4.14 — o segredo nao aparece no log RENDERIZADO', () => {
  it('o dado de entrada TEM segredo — senao esta busca mede zero', () => {
    expect(webhook.secret).toBe(SEGREDO);
    expect(SEGREDO.length).toBeGreaterThan(20);
  });

  it('o segredo do webhook nao esta no HTML da tela de entregas', async () => {
    const wrapper = await montar([ENTREGA_FALHADA, ENTREGA_OK]);

    expect(wrapper.html()).not.toContain(SEGREDO);
    expect(wrapper.text()).not.toContain(SEGREDO);
    // e a tela AINDA serve para o que existe
    expect(wrapper.text()).toContain('entrega-42');
  });
});
