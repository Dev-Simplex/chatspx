import { useTrackingDiagnostics } from '../useTrackingDiagnostics';

/**
 * A conta que o painel faz (bloco 5.14).
 *
 * Estes numeros viram resposta de suporte para o cliente ("esta entregando
 * 50%"), entao errar o DENOMINADOR nao e detalhe de arredondamento: e dizer ao
 * cliente que a integracao dele esta pior do que esta. Os casos abaixo cobrem
 * justamente as escolhas de denominador, que sao onde uma taxa mente.
 */
const erroHttp = status => {
  const erro = new Error(`HTTP ${status}`);
  erro.response = { status };
  return erro;
};

const entrega = (props = {}) => ({
  event_id: 'e',
  name: 'chatspx_lead',
  destination: 'meta_capi',
  status: 'sent',
  field_names: [],
  ...props,
});

beforeEach(() => {
  window.history.replaceState({}, '', '/app/accounts/3/settings/inboxes/7');
});

describe('5.14 — a taxa de entrega', () => {
  const comEntregas = async deliveries => {
    global.axios = { get: () => Promise.resolve({ data: { deliveries } }) };
    const d = useTrackingDiagnostics(7);
    await d.carregar();
    return d;
  };

  it('conta sobre o que foi TENTADO — `pending` fica fora do denominador', async () => {
    const d = await comEntregas([
      entrega({ event_id: '1', status: 'sent' }),
      entrega({ event_id: '2', status: 'failed' }),
      // a fila encheu: isto ainda nao foi tentado e nao pode derrubar a taxa
      entrega({ event_id: '3', status: 'pending' }),
      entrega({ event_id: '4', status: 'pending' }),
    ]);

    expect(d.deliveryRate.value).toBe(50);
  });

  it('`skipped` não é falha nem entrega — consentimento negado não é defeito', async () => {
    const d = await comEntregas([
      entrega({ event_id: '1', status: 'sent' }),
      entrega({ event_id: '2', status: 'skipped' }),
    ]);

    expect(d.deliveryRate.value).toBe(100);
  });

  it('`dead` conta como falha — a DLQ não pode sumir da conta', async () => {
    const d = await comEntregas([
      entrega({ event_id: '1', status: 'sent' }),
      entrega({ event_id: '2', status: 'dead' }),
    ]);

    expect(d.deliveryRate.value).toBe(50);
    expect(d.falhas.value).toBe(1);
  });

  it('sem nenhuma tentativa, a taxa é `null` e não 0%', async () => {
    // 0% diria "nada entrega"; `null` diz "ainda não dá para saber", e a tela
    // desenha "sem dados". São respostas diferentes para o cliente.
    const d = await comEntregas([entrega({ status: 'pending' })]);

    expect(d.deliveryRate.value).toBeNull();
  });
});

describe('5.14 — o EMQ', () => {
  it('faz média só dos que TÊM EMQ — destino sem a métrica não vira zero', async () => {
    global.axios = {
      get: () =>
        Promise.resolve({
          data: {
            deliveries: [
              entrega({ event_id: '1', emq: 9 }),
              entrega({ event_id: '2', emq: 8 }),
              // o GA4 não devolve EMQ: contar como 0 afundaria a média
              entrega({ event_id: '3', destination: 'ga4_mp', emq: null }),
            ],
          },
        }),
    };
    const d = useTrackingDiagnostics(7);
    await d.carregar();

    expect(d.emqAverage.value).toBe(8.5);
    expect(d.emqIsHealthy.value).toBe(true);
  });

  it('abaixo de 8 não é saudável — é a faixa que a Meta usa', async () => {
    global.axios = {
      get: () =>
        Promise.resolve({ data: { deliveries: [entrega({ emq: 6.4 })] } }),
    };
    const d = useTrackingDiagnostics(7);
    await d.carregar();

    expect(d.emqIsHealthy.value).toBe(false);
  });
});

describe('5.14 — os erros agrupados', () => {
  it('o mesmo erro cem vezes vira UMA linha com a contagem', async () => {
    global.axios = {
      get: () =>
        Promise.resolve({
          data: {
            deliveries: [
              ...Array.from({ length: 4 }, (_, i) =>
                entrega({
                  event_id: `a${i}`,
                  status: 'failed',
                  error_code: 'invalid_hash',
                })
              ),
              entrega({
                event_id: 'b',
                status: 'failed',
                error_code: 'bad_token',
              }),
            ],
          },
        }),
    };
    const d = useTrackingDiagnostics(7);
    await d.carregar();

    expect(d.errorGroups.value).toHaveLength(2);
    // o mais frequente vem primeiro: é o que o suporte tem de atacar
    expect(d.errorGroups.value[0]).toMatchObject({
      key: 'invalid_hash',
      count: 4,
    });
  });
});

describe('5.14 — quando a rota não existe', () => {
  it('404 vira "falta a rota", com o caminho — não vira erro genérico', async () => {
    global.axios = { get: () => Promise.reject(erroHttp(404)) };
    const d = useTrackingDiagnostics(7);
    await d.carregar();

    expect(d.missingEndpoint.value).toBe(
      '/api/v1/accounts/3/inboxes/7/tracking_deliveries'
    );
    expect(d.loadError.value).toBe('');
  });

  it('500 é erro de verdade e NÃO é confundido com rota ausente', async () => {
    global.axios = { get: () => Promise.reject(erroHttp(500)) };
    const d = useTrackingDiagnostics(7);
    await d.carregar();

    expect(d.missingEndpoint.value).toBe('');
    expect(d.loadError.value).toContain('500');
  });
});

describe('5.14 — o botão de teste', () => {
  it('a entrega nova entra no topo da lista, já limpa de PII', async () => {
    global.axios = {
      get: () => Promise.resolve({ data: { deliveries: [] } }),
      post: () =>
        Promise.resolve({
          data: {
            delivery: entrega({
              event_id: 'teste',
              status: 'failed',
              http_status: 400,
              error_message: 'em (ana@exemplo.com) is not a valid hash',
            }),
          },
        }),
    };
    const d = useTrackingDiagnostics(7);
    await d.carregar();
    const resultado = await d.enviarEventoDeTeste();

    expect(d.deliveries.value[0].event_id).toBe('teste');
    expect(resultado.http_status).toBe(400);
    // a limpeza acontece na leitura, não só no desenho
    expect(resultado.error_message).not.toContain('@');
  });
});
