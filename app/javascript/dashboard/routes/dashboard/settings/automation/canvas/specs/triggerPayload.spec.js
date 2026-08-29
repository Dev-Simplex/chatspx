/**
 * BLOCO 4.02 — O CANVAS NÃO PODE APAGAR O GATILHO DE CAPTURA.
 *
 * O canvas é o ÚNICO editor de fluxo do produto, e a tela do pré-chat (3.14) manda o admin para
 * lá. Ele não conhecia `widget_prechat`: caía no default `{ trigger_type: 'manual',
 * trigger_config: {} }`, e o controller aplica o jsonb cru. Medido no diagnóstico: abrir e salvar
 * um fluxo de captura APAGAVA `url_conditions`, `priority`, `inbox_ids` e `experiment` e o fluxo
 * deixava de ser captura — com 200 e sem aviso.
 *
 * A correção é ROUND-TRIP, não autoria: o canvas carimba o KIND no nó `trigger` (como já faz com
 * todos os outros gatilhos) e devolve a segmentação que carregou, intacta. Quem edita o alvo é
 * outra tela; o canvas só não pode perdê-lo.
 *
 * A outra metade da defesa é do servidor (`Flow#preserve_widget_prechat_targeting`) e está medida
 * em `spec/controllers/api/v1/accounts/flows_widget_prechat_round_trip_spec.rb`, contra o
 * controller e o serializador REAIS. Que o SFC de fato CHAME estas funções é medido em
 * `FlowCanvasView.prechat.spec.js` — módulo puro que ninguém chama passa no vácuo.
 */
import {
  WIDGET_PRECHAT_KIND,
  buildTriggerPayload,
  stampTriggerKind,
} from '../triggerPayload';

// A segmentação como o servidor a devolve — o MESMO literal que o rspec do 4.02 recebe
// (`segmentacao` em flows_widget_prechat_round_trip_spec.rb). Os dois lados têm de mudar juntos,
// e é por isso que os dois specs carregam o objeto inteiro em vez de um pedaço.
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

const fluxoDeCaptura = (trigger_config = SEGMENTACAO) => ({
  id: 9,
  name: 'Captura de precos',
  trigger_type: 'widget_prechat',
  trigger_config,
  definition: {
    nodes: [
      { id: 'trg', type: 'trigger' },
      { id: 'n1', type: 'action', action_name: 'send_message' },
    ],
    edges: [{ from: 'trg', to: 'n1' }],
  },
});

const triggerNodesOf = definition =>
  definition.nodes.filter(node => node.type === 'trigger');

describe('4.02 — round-trip do gatilho widget_prechat no canvas', () => {
  describe('stampTriggerKind — a ida (o que o canvas carrega)', () => {
    it('marca o nó trigger como gatilho de captura', () => {
      const flow = fluxoDeCaptura();
      const definition = stampTriggerKind(flow.definition, flow);

      expect(triggerNodesOf(definition)[0].trigger_kind).toBe(
        WIDGET_PRECHAT_KIND
      );
    });

    // O ALVO NÃO ENTRA NA `definition`. Ele mora em `flows.trigger_config`; uma cópia dele numa
    // segunda coluna seria um retrato que envelhece, e a próxima pessoa a ler `definition`
    // acharia que está lendo o alvo em vigor.
    it('não copia a segmentação para dentro da definition', () => {
      const flow = fluxoDeCaptura();
      const serializada = JSON.stringify(
        stampTriggerKind(flow.definition, flow)
      );

      expect(serializada).not.toContain('url_conditions');
      expect(serializada).not.toContain('captura-2026');
    });

    it('não mexe nos nós que não são gatilho', () => {
      const flow = fluxoDeCaptura();
      const definition = stampTriggerKind(flow.definition, flow);

      expect(definition.nodes[1]).toEqual(flow.definition.nodes[1]);
      expect(definition.edges).toEqual(flow.definition.edges);
    });

    it('é imutável: não escreve no objeto que veio do store', () => {
      const flow = fluxoDeCaptura();
      stampTriggerKind(flow.definition, flow);

      expect(flow.definition.nodes[0]).not.toHaveProperty('trigger_kind');
    });

    // CONTROLE — a marcação não pode vazar para os outros quatro gatilhos.
    it.each(['manual', 'conversation_event', 'keyword', 'external_webhook'])(
      'não marca nada num fluxo %s',
      trigger_type => {
        const flow = { ...fluxoDeCaptura(), trigger_type };
        const definition = stampTriggerKind(flow.definition, flow);

        expect(definition.nodes[0].trigger_kind).toBeUndefined();
      }
    );

    // `null` e não `undefined`: parâmetro com default só cai no default quando o argumento é
    // `undefined`, e o exemplo mediria a segmentação inteira achando que mediu a ausência dela.
    it('sobrevive a um fluxo de captura sem trigger_config gravado', () => {
      const flow = fluxoDeCaptura(null);
      const definition = stampTriggerKind(flow.definition, flow);

      expect(definition.nodes[0].trigger_kind).toBe(WIDGET_PRECHAT_KIND);
      expect(buildTriggerPayload(triggerNodesOf(definition), null)).toEqual({
        trigger_type: WIDGET_PRECHAT_KIND,
        trigger_config: {},
      });
    });
  });

  describe('buildTriggerPayload — a volta (o que o canvas grava)', () => {
    // O ACEITE DESTE BLOCO, em uma linha: ida e volta sem perda.
    it('faz o round-trip completo — carregar e salvar devolve o que estava lá', () => {
      const flow = fluxoDeCaptura();
      const definition = stampTriggerKind(flow.definition, flow);
      const payload = buildTriggerPayload(
        triggerNodesOf(definition),
        flow.trigger_config
      );

      expect(payload.trigger_type).toBe(flow.trigger_type);
      expect(payload.trigger_config).toEqual(flow.trigger_config);
    });

    // CONTROLE NEGATIVO do round-trip: sem o carimbo, o payload volta a ser o default que
    // apagava tudo. É a reprodução do defeito, dentro da suíte.
    it('sem o carimbo do kind, o mesmo fluxo cairia em manual — o defeito de origem', () => {
      const flow = fluxoDeCaptura();

      expect(
        buildTriggerPayload(
          triggerNodesOf(flow.definition),
          flow.trigger_config
        )
      ).toEqual({ trigger_type: 'manual', trigger_config: {} });
    });

    it('devolve uma CÓPIA da segmentação, não a referência do store', () => {
      const flow = fluxoDeCaptura();
      const definition = stampTriggerKind(flow.definition, flow);
      const payload = buildTriggerPayload(
        triggerNodesOf(definition),
        flow.trigger_config
      );

      expect(payload.trigger_config).not.toBe(flow.trigger_config);
    });

    it('o gatilho de captura vence o event_name herdado de uma conversão de gatilho', () => {
      const trigger = {
        id: 'trg',
        type: 'trigger',
        event_name: 'conversation_created',
        trigger_kind: WIDGET_PRECHAT_KIND,
      };

      expect(buildTriggerPayload([trigger], SEGMENTACAO)).toEqual({
        trigger_type: WIDGET_PRECHAT_KIND,
        trigger_config: SEGMENTACAO,
      });
    });

    // Os outros quatro gatilhos continuam exatamente como eram — esta é a garantia de que a
    // mudança não é uma reescrita do projetor, e sim um ramo novo nele.
    it('mantém keyword', () => {
      const payload = buildTriggerPayload([
        {
          type: 'trigger',
          trigger_kind: 'keyword',
          keywords: [' orcamento ', '', 'preco'],
          match: 'exact',
          direction: 'incoming',
        },
      ]);

      expect(payload).toEqual({
        trigger_type: 'keyword',
        trigger_config: {
          keywords: ['orcamento', 'preco'],
          match: 'exact',
          direction: 'incoming',
        },
      });
    });

    it('mantém schedule por intervalo e por cron', () => {
      expect(
        buildTriggerPayload([
          {
            type: 'trigger',
            trigger_kind: 'schedule',
            schedule: { mode: 'interval', every: '3', unit: 'hours' },
          },
        ])
      ).toEqual({
        trigger_type: 'schedule',
        trigger_config: { mode: 'interval', every: 3, unit: 'hours' },
      });

      expect(
        buildTriggerPayload([
          {
            type: 'trigger',
            trigger_kind: 'schedule',
            schedule: { mode: 'cron', cron: ' 0 9 * * * ' },
          },
        ])
      ).toEqual({
        trigger_type: 'schedule',
        trigger_config: { mode: 'cron', cron: '0 9 * * *' },
      });
    });

    it('mantém external_webhook sem deixar o cliente propor token', () => {
      expect(
        buildTriggerPayload([
          {
            type: 'trigger',
            trigger_kind: 'webhook',
            webhook_token: 'eco-de-exibicao',
          },
        ])
      ).toEqual({ trigger_type: 'external_webhook', trigger_config: {} });
    });

    it('mantém conversation_event, com event_names quando há mais de um gatilho', () => {
      const um = buildTriggerPayload([
        { type: 'trigger', event_name: 'conversation_created' },
      ]);
      expect(um.trigger_type).toBe('conversation_event');
      expect(um.trigger_config).toEqual({
        event_name: 'conversation_created',
        direction: 'both',
      });
      expect(um.trigger_config.event_names).toBeUndefined();

      const dois = buildTriggerPayload([
        { type: 'trigger', event_name: 'conversation_created' },
        { type: 'trigger', event_name: 'conversation_resolved' },
      ]);
      expect(dois.trigger_config.event_names).toEqual([
        'conversation_created',
        'conversation_resolved',
      ]);
    });

    it('sem nó de gatilho cai em manual, como antes', () => {
      expect(buildTriggerPayload([])).toEqual({
        trigger_type: 'manual',
        trigger_config: {},
      });
    });
  });
});
