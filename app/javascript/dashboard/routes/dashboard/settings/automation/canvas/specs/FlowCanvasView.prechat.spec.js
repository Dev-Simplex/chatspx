/**
 * BLOCO 4.02 — A FIAÇÃO, e não só a função pura.
 *
 * `triggerPayload.spec.js` mede as duas funções com o dado real. Este spec mede a única coisa que
 * aquele não pode medir: que o `FlowCanvasView` de fato as CHAME — na carga e no save. Um módulo
 * puro correto que ninguém chama passa no vácuo, e o defeito de origem deste bloco era
 * exatamente um ramo que ninguém alcançava.
 *
 * O caminho exercitado é o real e inteiro: monta o SFC na rota de edição, deixa o `onMounted`
 * carregar o fluxo pelo store, clica em SALVAR e inspeciona o payload que chega ao
 * `flows/update` — o mesmo objeto que o rspec do 4.02 recebe do outro lado do fio.
 */
import { shallowMount, flushPromises } from '@vue/test-utils';
import FlowCanvasView from '../FlowCanvasView.vue';

const dispatch = vi.fn();

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { flowId: '9', accountId: '1' }, query: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  onBeforeRouteLeave: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch, getters: { 'flows/getFlow': () => null } }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// A segmentação como o servidor a serializa — o mesmo literal do rspec do 4.02.
const SEGMENTACAO = {
  url_conditions: [{ operator: 'contains', value: '/precos' }],
  match: 'all',
  priority: 7,
  inbox_ids: [12],
  devices: ['desktop'],
  business_hours_only: false,
  utm: { utm_source: 'google' },
  experiment: { key: 'captura-2026', weight: 50 },
};

// O `action_params` NÃO é decoração: `flowValidation#checkTextAction` trata `send_message` de
// corpo em branco como ERRO, e o `graphGatePassed` do save aborta antes de chegar ao
// `flows/update`. Sem ele os três exemplos abaixo falham por "payload undefined" e param de
// medir o round-trip — que é justamente o que este arquivo existe para medir.
const DEFINITION = {
  nodes: [
    { id: 'trg', type: 'trigger' },
    {
      id: 'n1',
      type: 'action',
      action_name: 'send_message',
      action_params: ['Ola, em que posso ajudar?'],
    },
  ],
  edges: [{ from: 'trg', to: 'n1' }],
};

const flowDoServidor = (extra = {}) => ({
  id: 9,
  name: 'Captura de precos',
  trigger_type: 'widget_prechat',
  trigger_config: SEGMENTACAO,
  definition: DEFINITION,
  ...extra,
});

const abrirNoCanvas = async flow => {
  dispatch.mockImplementation(action => {
    if (action === 'flows/show') return Promise.resolve(flow);
    if (action === 'flows/update') return Promise.resolve(flow);
    return Promise.resolve({});
  });

  const wrapper = shallowMount(FlowCanvasView);
  await flushPromises();
  return wrapper;
};

const salvar = async wrapper => {
  await wrapper.find('[data-testid="canvas-save"]').trigger('click');
  await flushPromises();
  return dispatch.mock.calls.find(([action]) => action === 'flows/update')?.[1];
};

beforeEach(() => dispatch.mockReset());

describe('4.02 — o canvas salvando um fluxo de captura', () => {
  it('devolve o gatilho widget_prechat com a segmentação intacta', async () => {
    const payload = await salvar(await abrirNoCanvas(flowDoServidor()));

    expect(payload.trigger_type).toBe('widget_prechat');
    expect(payload.trigger_config).toEqual(SEGMENTACAO);
  });

  // O alvo viaja em `trigger_config` e SÓ nele. Uma cópia dentro da `definition` seria um
  // retrato que envelhece numa segunda coluna.
  it('não copia a segmentação para dentro da definition', async () => {
    const payload = await salvar(await abrirNoCanvas(flowDoServidor()));

    expect(JSON.stringify(payload.definition)).not.toContain('url_conditions');
    expect(JSON.stringify(payload.definition)).not.toContain('captura-2026');
  });

  // BLOCO 6.05 — O EXPERIMENTO A/B ATRAVESSA UMA EDIÇÃO DE VERDADE.
  //
  // `trigger_config.experiment` é a chave mais frágil do alvo: nenhuma tela do canvas a edita,
  // então ela não pode ser corrigida quando some — só sobrevive ou desaparece, e o relatório do
  // A/B passa a medir uma variante que deixou de receber tráfego.
  //
  // O exemplo acima salva sem tocar em nada, e um round-trip de save vazio pode passar por
  // motivo errado. Aqui o admin RENOMEIA o fluxo antes de salvar: o save leva uma alteração
  // real, e a chave do experimento tem de chegar do outro lado com a mesma forma
  // (`{ key, weight }`) que `Flow::AbExperiment#key_for` e `#weight_for` leem.
  it('devolve o experimento A/B intacto depois de uma edição de verdade', async () => {
    const wrapper = await abrirNoCanvas(flowDoServidor());
    await wrapper
      .find('[data-testid="canvas-name"]')
      .setValue('Captura de precos v2');

    const payload = await salvar(wrapper);

    expect(payload.name).toBe('Captura de precos v2');
    // Sem o `trigger_type` o resto não vale nada: `Flows::WidgetPrechatResolver` filtra pelo
    // ENUM, e um fluxo demovido a `manual` nunca mais é entregue — o experimento morre com a
    // segmentação inteira preservada no jsonb, que é o modo de falha mais difícil de enxergar.
    expect(payload.trigger_type).toBe('widget_prechat');
    expect(payload.trigger_config.experiment).toEqual({
      key: 'captura-2026',
      weight: 50,
    });
  });

  // CONTROLE — os outros gatilhos continuam projetados como sempre foram. Sem este exemplo, a
  // correção poderia ter transformado TODO fluxo em captura e ainda assim ficar verde.
  it('mantém um fluxo de evento como conversation_event', async () => {
    const flow = flowDoServidor({
      trigger_type: 'conversation_event',
      trigger_config: { event_name: 'conversation_created' },
      definition: {
        ...DEFINITION,
        nodes: [
          { id: 'trg', type: 'trigger', event_name: 'conversation_created' },
          DEFINITION.nodes[1],
        ],
      },
    });

    const payload = await salvar(await abrirNoCanvas(flow));

    expect(payload.trigger_type).toBe('conversation_event');
    expect(payload.trigger_config.event_name).toBe('conversation_created');
  });
});
