import { flatToDefinition, definitionToFlat } from '../flatToDefinition';

describe('flatToDefinition', () => {
  it('creates a lone trigger node for an empty rule', () => {
    const def = flatToDefinition();
    expect(def.nodes).toEqual([{ id: 'n1', type: 'trigger' }]);
    expect(def.edges).toEqual([]);
  });

  it('creates a lone trigger node for an empty object', () => {
    expect(flatToDefinition({})).toEqual({
      nodes: [{ id: 'n1', type: 'trigger' }],
      edges: [],
    });
  });

  it('attaches event_name to the trigger node when present', () => {
    const def = flatToDefinition({ event_name: 'conversation_created' });
    expect(def.nodes[0]).toEqual({
      id: 'n1',
      type: 'trigger',
      event_name: 'conversation_created',
    });
  });

  it('does not attach event_name when it is absent', () => {
    const def = flatToDefinition({ actions: [] });
    expect(def.nodes[0]).not.toHaveProperty('event_name');
  });

  describe('conditions', () => {
    it('adds a condition node linked to the trigger by a branch-less edge', () => {
      const conditions = [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: ['open'],
        },
      ];
      const def = flatToDefinition({ event_name: 'x', conditions });
      const condition = def.nodes.find(node => node.type === 'condition');
      expect(condition).toMatchObject({ type: 'condition', conditions });
      expect(def.edges).toContainEqual({ from: 'n1', to: condition.id });
    });
  });

  describe('actions', () => {
    it('chains actions linearly from the trigger when there are no conditions', () => {
      const actions = [
        { action_name: 'add_label', action_params: [1] },
        { action_name: 'assign_team', action_params: [2] },
      ];
      const def = flatToDefinition({ event_name: 'x', actions });
      expect(def.nodes).toHaveLength(3);
      const [, second, third] = def.nodes;
      expect(second).toMatchObject({
        type: 'action',
        action_name: 'add_label',
        action_params: [1],
      });
      expect(third).toMatchObject({
        type: 'action',
        action_name: 'assign_team',
        action_params: [2],
      });
      expect(def.edges).toEqual([
        { from: 'n1', to: 'n2' },
        { from: 'n2', to: 'n3' },
      ]);
    });

    it('hangs the first action off the condition true branch, then chains linearly', () => {
      const def = flatToDefinition({
        event_name: 'x',
        conditions: [{ attribute_key: 'a' }],
        actions: [
          { action_name: 'add_label', action_params: [1] },
          { action_name: 'mute_conversation', action_params: [] },
        ],
      });
      expect(def.edges).toEqual([
        { from: 'n1', to: 'n2' }, // trigger -> condition (no branch)
        { from: 'n2', to: 'n3', branch: 'true' }, // condition true -> first action
        { from: 'n3', to: 'n4' }, // action -> action (linear)
      ]);
    });

    it('preserves action_params verbatim', () => {
      const action_params = { message: 'oi', nested: { list: [1, 2] } };
      const def = flatToDefinition({
        actions: [{ action_name: 'send_message', action_params }],
      });
      const node = def.nodes.find(item => item.type === 'action');
      expect(node.action_params).toEqual(action_params);
    });
  });
});

describe('definitionToFlat', () => {
  it('returns empty scaffolding for an empty definition', () => {
    expect(definitionToFlat()).toEqual({
      event_name: null,
      conditions: [],
      actions: [],
    });
    expect(definitionToFlat({})).toEqual({
      event_name: null,
      conditions: [],
      actions: [],
    });
  });

  it('reads event_name from the trigger node', () => {
    const def = {
      nodes: [
        { id: 'n1', type: 'trigger', event_name: 'conversation_updated' },
      ],
      edges: [],
    };
    expect(definitionToFlat(def).event_name).toBe('conversation_updated');
  });

  it('collects conditions from the condition node', () => {
    const conditions = [{ attribute_key: 'status' }];
    const def = {
      nodes: [
        { id: 'n1', type: 'trigger' },
        { id: 'n2', type: 'condition', conditions },
      ],
      edges: [{ from: 'n1', to: 'n2' }],
    };
    expect(definitionToFlat(def).conditions).toEqual(conditions);
  });

  it('walks the chain and collects actions in traversal order', () => {
    const def = {
      nodes: [
        { id: 'n1', type: 'trigger' },
        {
          id: 'n2',
          type: 'action',
          action_name: 'add_label',
          action_params: [1],
        },
        {
          id: 'n3',
          type: 'action',
          action_name: 'assign_team',
          action_params: [2],
        },
      ],
      edges: [
        { from: 'n1', to: 'n2' },
        { from: 'n2', to: 'n3' },
      ],
    };
    expect(definitionToFlat(def).actions).toEqual([
      { action_name: 'add_label', action_params: [1] },
      { action_name: 'assign_team', action_params: [2] },
    ]);
  });

  it('follows the true branch out of a condition', () => {
    const def = {
      nodes: [
        { id: 'n1', type: 'trigger' },
        { id: 'n2', type: 'condition', conditions: [] },
        {
          id: 'yes',
          type: 'action',
          action_name: 'add_label',
          action_params: [],
        },
        {
          id: 'no',
          type: 'action',
          action_name: 'remove_label',
          action_params: [],
        },
      ],
      edges: [
        { from: 'n1', to: 'n2' },
        { from: 'n2', to: 'yes', branch: 'true' },
        { from: 'n2', to: 'no', branch: 'false' },
      ],
    };
    expect(definitionToFlat(def).actions).toEqual([
      { action_name: 'add_label', action_params: [] },
    ]);
  });

  it('falls back to the first outgoing edge when the true branch is missing', () => {
    const def = {
      nodes: [
        { id: 'n1', type: 'trigger' },
        { id: 'n2', type: 'condition', conditions: [] },
        {
          id: 'only',
          type: 'action',
          action_name: 'mute_conversation',
          action_params: [],
        },
      ],
      edges: [
        { from: 'n1', to: 'n2' },
        { from: 'n2', to: 'only', branch: 'false' }, // no 'true' edge exists
      ],
    };
    expect(definitionToFlat(def).actions).toEqual([
      { action_name: 'mute_conversation', action_params: [] },
    ]);
  });

  it('starts from the first node when there is no trigger', () => {
    const def = {
      nodes: [
        {
          id: 'a',
          type: 'action',
          action_name: 'add_label',
          action_params: [],
        },
      ],
      edges: [],
    };
    const flat = definitionToFlat(def);
    expect(flat.event_name).toBeNull();
    expect(flat.actions).toEqual([
      { action_name: 'add_label', action_params: [] },
    ]);
  });

  it('does not loop forever on a cyclic definition', () => {
    const def = {
      nodes: [
        { id: 'n1', type: 'trigger' },
        {
          id: 'n2',
          type: 'action',
          action_name: 'add_label',
          action_params: [],
        },
      ],
      edges: [
        { from: 'n1', to: 'n2' },
        { from: 'n2', to: 'n1' }, // back to the trigger
      ],
    };
    expect(definitionToFlat(def).actions).toEqual([
      { action_name: 'add_label', action_params: [] },
    ]);
  });

  it('handles arbitrary (non "nX") node ids', () => {
    const def = {
      nodes: [
        {
          id: 'trigger-node',
          type: 'trigger',
          event_name: 'conversation_created',
        },
        {
          id: 'act',
          type: 'action',
          action_name: 'add_label',
          action_params: [],
        },
      ],
      edges: [{ from: 'trigger-node', to: 'act' }],
    };
    const flat = definitionToFlat(def);
    expect(flat.event_name).toBe('conversation_created');
    expect(flat.actions).toEqual([
      { action_name: 'add_label', action_params: [] },
    ]);
  });
});

describe('round-trip: definitionToFlat(flatToDefinition(rule))', () => {
  it('recovers a rule with event_name, conditions and ordered actions', () => {
    const rule = {
      event_name: 'conversation_created',
      conditions: [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: ['open'],
        },
      ],
      actions: [
        { action_name: 'add_label', action_params: [12] },
        { action_name: 'assign_team', action_params: [3] },
        { action_name: 'send_message', action_params: ['hi'] },
      ],
    };
    expect(definitionToFlat(flatToDefinition(rule))).toEqual(rule);
  });

  it('recovers an actions-only rule (no conditions)', () => {
    const rule = {
      event_name: 'conversation_updated',
      conditions: [],
      actions: [{ action_name: 'mute_conversation', action_params: [] }],
    };
    expect(definitionToFlat(flatToDefinition(rule))).toEqual(rule);
  });

  it('normalizes an empty rule to null event / empty collections', () => {
    expect(definitionToFlat(flatToDefinition({}))).toEqual({
      event_name: null,
      conditions: [],
      actions: [],
    });
  });

  it('preserves action order across the round trip', () => {
    const actions = ['a', 'b', 'c', 'd'].map((name, index) => ({
      action_name: name,
      action_params: [index],
    }));
    const rule = { event_name: 'x', conditions: [], actions };
    expect(definitionToFlat(flatToDefinition(rule)).actions).toEqual(actions);
  });
});
