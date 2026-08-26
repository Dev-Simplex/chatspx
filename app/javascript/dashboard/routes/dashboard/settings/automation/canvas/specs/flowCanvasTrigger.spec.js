import { describe, it, expect } from 'vitest';
import {
  buildTriggerPayload,
  mergeTriggerConfig,
  projectInboxCondition,
  inboxIdsFromConditions,
  autoConnectTarget,
  supportsInboxFilter,
} from '../FlowCanvasView.vue';

// Condição não-inbox de um flow migrado de AutomationRule (Flows::BackfillService copia as
// `conditions` da regra tal e qual).
const statusCondition = (extra = {}) => ({
  attribute_key: 'status',
  filter_operator: 'equal_to',
  values: ['open'],
  query_operator: null,
  custom_attribute_type: '',
  ...extra,
});

const inboxCondition = (values, extra = {}) => ({
  attribute_key: 'inbox_id',
  filter_operator: 'equal_to',
  values,
  query_operator: null,
  custom_attribute_type: '',
  ...extra,
});

const eventTrigger = (extra = {}) => ({
  id: 'trigger',
  type: 'trigger',
  trigger_kind: 'event',
  event_name: 'conversation_created',
  ...extra,
});

describe('mergeTriggerConfig', () => {
  // O controller SUBSTITUI a coluna jsonb inteira: o que não voltar no payload é APAGADO.
  it('preserva as chaves que o canvas não projeta', () => {
    const merged = mergeTriggerConfig(
      {
        event_name: 'conversation_created',
        conditions: [statusCondition()],
        backfill_source: 'automation_rule:42',
        last_fired_at: '2026-08-01T10:00:00Z',
        webhook_token: 'abc',
      },
      { event_name: 'conversation_resolved', direction: 'both' }
    );

    expect(merged.conditions).toEqual([statusCondition()]);
    expect(merged.backfill_source).toBe('automation_rule:42');
    expect(merged.last_fired_at).toBe('2026-08-01T10:00:00Z');
    expect(merged.webhook_token).toBe('abc');
    expect(merged.event_name).toBe('conversation_resolved');
  });

  // As chaves que a projeção governa não podem sobreviver a uma troca de tipo de gatilho —
  // um `event_names` velho faria o flow continuar disparando num evento já removido.
  it('descarta as chaves governadas pela projeção', () => {
    const merged = mergeTriggerConfig(
      { event_names: ['a', 'b'], keywords: ['oi'], match: 'exact' },
      { event_name: 'conversation_created', direction: 'both' }
    );

    expect(merged.event_names).toBeUndefined();
    expect(merged.keywords).toBeUndefined();
    expect(merged.match).toBeUndefined();
  });

  it('aceita um trigger_config original ausente', () => {
    expect(mergeTriggerConfig(undefined, { mode: 'cron' })).toEqual({
      mode: 'cron',
    });
  });
});

describe('buildTriggerPayload', () => {
  // O bug: salvar pelo canvas apagava `conditions` (única gate dos flows migrados) e o flow
  // passava a disparar em TODA conversa.
  it('não apaga as conditions do flow ao salvar um gatilho por evento', () => {
    const payload = buildTriggerPayload([eventTrigger()], {
      event_name: 'conversation_created',
      conditions: [statusCondition()],
      backfill_source: 'automation_rule:42',
    });

    expect(payload.trigger_type).toBe('conversation_event');
    expect(payload.trigger_config.conditions).toEqual([statusCondition()]);
    expect(payload.trigger_config.backfill_source).toBe('automation_rule:42');
  });

  it('preserva as conditions num gatilho que não tem seletor de caixa', () => {
    const payload = buildTriggerPayload(
      [
        {
          id: 'trigger',
          type: 'trigger',
          trigger_kind: 'schedule',
          schedule: { mode: 'cron', cron: '0 9 * * 1' },
        },
      ],
      { conditions: [statusCondition()], backfill_source: 'automation_rule:7' }
    );

    expect(payload.trigger_type).toBe('schedule');
    expect(payload.trigger_config.conditions).toEqual([statusCondition()]);
    expect(payload.trigger_config.backfill_source).toBe('automation_rule:7');
  });

  it('projeta inbox_ids em conditions no formato do backend', () => {
    const payload = buildTriggerPayload(
      [eventTrigger({ inbox_ids: [1, 2] })],
      {}
    );

    expect(payload.trigger_config.conditions).toEqual([
      {
        attribute_key: 'inbox_id',
        filter_operator: 'equal_to',
        values: [1, 2],
        custom_attribute_type: '',
        query_operator: null,
      },
    ]);
  });

  // Round-trip: hidratar do trigger_config salvo e salvar de novo devolve o MESMO gate.
  it('faz round-trip preservando as conditions não-inbox', () => {
    const saved = {
      event_name: 'conversation_created',
      conditions: [
        statusCondition({ query_operator: 'and' }),
        inboxCondition([3]),
      ],
      backfill_source: 'automation_rule:42',
    };

    const inboxIds = inboxIdsFromConditions(saved.conditions);
    const payload = buildTriggerPayload(
      [eventTrigger({ inbox_ids: inboxIds })],
      saved
    );

    expect(inboxIds).toEqual([3]);
    expect(payload.trigger_config.conditions).toEqual(saved.conditions);
    expect(payload.trigger_config.backfill_source).toBe('automation_rule:42');
  });

  it('remove a condição de inbox quando o usuário limpa o campo', () => {
    const payload = buildTriggerPayload([eventTrigger({ inbox_ids: [] })], {
      conditions: [
        statusCondition({ query_operator: 'and' }),
        inboxCondition([3]),
      ],
    });

    expect(payload.trigger_config.conditions).toEqual([statusCondition()]);
  });

  it('grava event_names só com mais de um nó de gatilho', () => {
    const single = buildTriggerPayload([eventTrigger()], {});
    expect(single.trigger_config.event_names).toBeUndefined();

    const multi = buildTriggerPayload(
      [
        eventTrigger(),
        eventTrigger({ id: 't2', event_name: 'conversation_resolved' }),
      ],
      {}
    );
    expect(multi.trigger_config.event_names).toEqual([
      'conversation_created',
      'conversation_resolved',
    ]);
  });
});

describe('projectInboxCondition', () => {
  it('substitui a condição de inbox no LUGAR dela, preservando a ordem', () => {
    const original = [
      inboxCondition([1], { query_operator: 'and' }),
      statusCondition(),
    ];

    const next = projectInboxCondition(original, [7, 8]);

    expect(next.map(c => c.attribute_key)).toEqual(['inbox_id', 'status']);
    expect(next[0].values).toEqual([7, 8]);
    expect(next[0].query_operator).toBe('and');
    expect(next[1]).toEqual(statusCondition());
  });

  // Só a última condição pode ficar sem query_operator — um "AND" sobrando quebraria o SQL do
  // ConditionsFilterService e a gate reprovaria toda conversa.
  it('normaliza os query_operator ao acrescentar a condição de inbox', () => {
    const next = projectInboxCondition([statusCondition()], [5]);

    expect(next).toHaveLength(2);
    expect(next[0].query_operator).toBe('and');
    expect(next[1].query_operator).toBeNull();
  });

  it('devolve as conditions intactas quando não há inbox nem selecionada nem salva', () => {
    const original = [statusCondition()];
    expect(projectInboxCondition(original, [])).toBe(original);
    expect(projectInboxCondition(undefined, undefined)).toEqual([]);
  });

  // Uma condição de inbox com outro operador (herdada de uma AutomationRule) não pertence ao
  // seletor: sobrescrevê-la inverteria o sentido do gate em silêncio.
  it('não toca numa condição de inbox com outro operador', () => {
    const original = [
      { ...inboxCondition([1]), filter_operator: 'not_equal_to' },
    ];

    expect(inboxIdsFromConditions(original)).toEqual([]);
    expect(projectInboxCondition(original, [])).toBe(original);
    expect(projectInboxCondition(original, [9])[0].filter_operator).toBe(
      'not_equal_to'
    );
  });
});

describe('inboxIdsFromConditions', () => {
  it('hidrata os ids a partir da condição de inbox salva', () => {
    expect(
      inboxIdsFromConditions([statusCondition(), inboxCondition([4, 5])])
    ).toEqual([4, 5]);
  });

  it('devolve vazio (= todas as caixas) sem condição de inbox', () => {
    expect(inboxIdsFromConditions([statusCondition()])).toEqual([]);
    expect(inboxIdsFromConditions(undefined)).toEqual([]);
  });
});

describe('supportsInboxFilter', () => {
  it('vale para os gatilhos por evento e por palavra-chave', () => {
    expect(supportsInboxFilter({ trigger_kind: 'event' })).toBe(true);
    expect(supportsInboxFilter({ trigger_kind: 'keyword' })).toBe(true);
    // Nó legado sem trigger_kind é 'event'.
    expect(supportsInboxFilter({})).toBe(true);
    expect(supportsInboxFilter({ trigger_kind: 'schedule' })).toBe(false);
    expect(supportsInboxFilter({ trigger_kind: 'webhook' })).toBe(false);
  });
});

describe('autoConnectTarget', () => {
  const nodes = [
    { id: 'n1', type: 'trigger' },
    { id: 'n2', type: 'action' },
    { id: 'n3', type: 'action' },
  ];

  it('liga no bloco SELECIONADO, não no último', () => {
    const { prev, autoConnected } = autoConnectTarget(nodes[1], nodes, []);

    expect(prev.id).toBe('n2');
    expect(autoConnected).toBe(true);
  });

  it('cai no último bloco quando não há seleção', () => {
    const { prev, autoConnected } = autoConnectTarget(null, nodes, []);

    expect(prev.id).toBe('n3');
    expect(autoConnected).toBe(true);
  });

  it('NÃO auto-liga a partir de um bloco de ramificação', () => {
    ['condition', 'router', 'wait_for_reply'].forEach(type => {
      const branch = { id: 'b1', type };
      const { prev, autoConnected } = autoConnectTarget(
        branch,
        [...nodes, branch],
        []
      );

      expect(prev).toBe(branch);
      expect(autoConnected).toBe(false);
    });
  });

  it('não auto-liga um bloco que já tem aresta de saída', () => {
    const { autoConnected } = autoConnectTarget(nodes[1], nodes, [
      { from: 'n2', to: 'n3' },
    ]);

    expect(autoConnected).toBe(false);
  });

  it('não liga nada num canvas vazio', () => {
    expect(autoConnectTarget(null, [], [])).toEqual({
      prev: null,
      autoConnected: false,
    });
  });
});
