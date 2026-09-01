import {
  computeTreeLayout,
  estimateNodeHeight,
  H_SPACING,
  NODE_WIDTH,
  V_SPACING,
} from '../flowLayout';

describe('computeTreeLayout', () => {
  describe('empty / degenerate input', () => {
    it('returns an empty Map when called with no argument', () => {
      const positions = computeTreeLayout();
      expect(positions).toBeInstanceOf(Map);
      expect(positions.size).toBe(0);
    });

    it('returns an empty Map for a definition without nodes', () => {
      expect(computeTreeLayout({}).size).toBe(0);
      expect(computeTreeLayout({ nodes: [] }).size).toBe(0);
      expect(computeTreeLayout({ nodes: [], edges: [] }).size).toBe(0);
    });

    it('tolerates non-array nodes/edges without throwing', () => {
      expect(computeTreeLayout({ nodes: null, edges: null }).size).toBe(0);
    });
  });

  describe('single node', () => {
    it('places a lone node at the origin column', () => {
      const positions = computeTreeLayout({
        nodes: [{ id: 'n1', type: 'trigger' }],
        edges: [],
      });
      expect(positions.size).toBe(1);
      expect(positions.get('n1')).toEqual({ x: 0, y: 0 });
    });
  });

  describe('linear chain — children below their parent', () => {
    const definition = {
      nodes: [
        { id: 'n1', type: 'trigger' },
        { id: 'n2', type: 'action', action_name: 'add_label' },
        { id: 'n3', type: 'action', action_name: 'assign_team' },
      ],
      edges: [
        { from: 'n1', to: 'n2' },
        { from: 'n2', to: 'n3' },
      ],
    };

    it('stacks each child in the same column as its parent', () => {
      const p = computeTreeLayout(definition);
      expect(p.get('n1').x).toBe(p.get('n2').x);
      expect(p.get('n2').x).toBe(p.get('n3').x);
    });

    it('increases depth (y) by V_SPACING per generation', () => {
      const p = computeTreeLayout(definition);
      expect(p.get('n1').y).toBe(0);
      expect(p.get('n2').y).toBe(V_SPACING);
      expect(p.get('n3').y).toBe(2 * V_SPACING);
    });
  });

  describe('condition — branches open side by side', () => {
    const definition = {
      nodes: [
        { id: 'n1', type: 'trigger' },
        { id: 'c', type: 'condition' },
        { id: 'yes', type: 'action', action_name: 'add_label' },
        { id: 'no', type: 'action', action_name: 'remove_label' },
      ],
      edges: [
        { from: 'n1', to: 'c' },
        { from: 'c', to: 'yes', branch: 'true' },
        { from: 'c', to: 'no', branch: 'false' },
      ],
    };

    it('places the two branch children in different columns at the same depth', () => {
      const p = computeTreeLayout(definition);
      expect(p.get('yes').y).toBe(p.get('no').y);
      expect(p.get('yes').x).not.toBe(p.get('no').x);
    });

    it('orders the true branch to the left of the false branch', () => {
      const p = computeTreeLayout(definition);
      expect(p.get('yes').x).toBeLessThan(p.get('no').x);
    });

    it('separates the sibling columns by exactly H_SPACING', () => {
      const p = computeTreeLayout(definition);
      expect(p.get('no').x - p.get('yes').x).toBe(H_SPACING);
    });

    it('centers the condition over the midpoint of its branches', () => {
      const p = computeTreeLayout(definition);
      const midpoint = (p.get('yes').x + p.get('no').x) / 2;
      expect(p.get('c').x).toBe(midpoint);
      expect(p.get('c').x).toBeGreaterThan(p.get('yes').x);
      expect(p.get('c').x).toBeLessThan(p.get('no').x);
    });
  });

  describe('router — routes in declared order, fallback last', () => {
    const definition = {
      nodes: [
        {
          id: 'r',
          type: 'router',
          routes: [{ key: 'k1' }, { key: 'k2' }],
          fallback_key: 'fb',
        },
        { id: 'a', type: 'action', action_name: 'add_label' },
        { id: 'b', type: 'action', action_name: 'remove_label' },
        { id: 'c', type: 'action', action_name: 'assign_team' },
      ],
      // deliberately declared out of order to prove branchOrder sorting
      edges: [
        { from: 'r', to: 'c', branch: 'fb' },
        { from: 'r', to: 'b', branch: 'k2' },
        { from: 'r', to: 'a', branch: 'k1' },
      ],
    };

    it('lays out route columns in declared order with the fallback on the far right', () => {
      const p = computeTreeLayout(definition);
      expect(p.get('a').x).toBeLessThan(p.get('b').x);
      expect(p.get('b').x).toBeLessThan(p.get('c').x);
    });

    it('keeps every route at the same depth', () => {
      const p = computeTreeLayout(definition);
      expect(p.get('a').y).toBe(p.get('b').y);
      expect(p.get('b').y).toBe(p.get('c').y);
    });
  });

  describe('cycle safety', () => {
    it('does not hang and returns finite positions for a pure cycle (no root)', () => {
      const definition = {
        nodes: [
          { id: 'a', type: 'action', action_name: 'x' },
          { id: 'b', type: 'action', action_name: 'y' },
          { id: 'c', type: 'action', action_name: 'z' },
        ],
        edges: [
          { from: 'a', to: 'b' },
          { from: 'b', to: 'c' },
          { from: 'c', to: 'a' },
        ],
      };
      const p = computeTreeLayout(definition);
      expect(p.size).toBe(3);
      ['a', 'b', 'c'].forEach(id => {
        expect(Number.isFinite(p.get(id).x)).toBe(true);
        expect(Number.isFinite(p.get(id).y)).toBe(true);
      });
    });

    it('handles a self-loop without infinite recursion', () => {
      const definition = {
        nodes: [{ id: 'a', type: 'action', action_name: 'x' }],
        edges: [{ from: 'a', to: 'a' }],
      };
      const p = computeTreeLayout(definition);
      expect(p.size).toBe(1);
      expect(Number.isFinite(p.get('a').x)).toBe(true);
      expect(Number.isFinite(p.get('a').y)).toBe(true);
    });

    it('handles a back-edge downstream of a real root', () => {
      const definition = {
        nodes: [
          { id: 'n1', type: 'trigger' },
          { id: 'n2', type: 'action', action_name: 'x' },
          { id: 'n3', type: 'action', action_name: 'y' },
        ],
        edges: [
          { from: 'n1', to: 'n2' },
          { from: 'n2', to: 'n3' },
          { from: 'n3', to: 'n2' },
        ],
      };
      const p = computeTreeLayout(definition);
      expect(p.size).toBe(3);
      expect(p.get('n1').y).toBe(0);
      ['n1', 'n2', 'n3'].forEach(id => {
        expect(Number.isFinite(p.get(id).x)).toBe(true);
        expect(Number.isFinite(p.get(id).y)).toBe(true);
      });
    });
  });

  describe('orphan / disconnected nodes', () => {
    it('assigns a position to a node unreachable from any root', () => {
      const definition = {
        nodes: [
          { id: 'n1', type: 'trigger' },
          { id: 'n2', type: 'action', action_name: 'x' },
          // an island cycle unreachable from the trigger
          { id: 'x', type: 'action', action_name: 'a' },
          { id: 'y', type: 'action', action_name: 'b' },
        ],
        edges: [
          { from: 'n1', to: 'n2' },
          { from: 'x', to: 'y' },
          { from: 'y', to: 'x' },
        ],
      };
      const p = computeTreeLayout(definition);
      expect(p.has('x')).toBe(true);
      expect(p.has('y')).toBe(true);
      expect(Number.isFinite(p.get('x').x)).toBe(true);
      expect(Number.isFinite(p.get('y').x)).toBe(true);
    });

    it('tiles multiple roots side by side at depth 0', () => {
      const definition = {
        nodes: [
          { id: 'r1', type: 'trigger' },
          { id: 'r2', type: 'trigger' },
        ],
        edges: [],
      };
      const p = computeTreeLayout(definition);
      expect(p.get('r1').x).not.toBe(p.get('r2').x);
      expect(p.get('r1').y).toBe(0);
      expect(p.get('r2').y).toBe(0);
    });
  });

  describe('completeness of the position map', () => {
    it('returns a position for every node id in the definition', () => {
      const definition = {
        nodes: [
          { id: 'n1', type: 'trigger' },
          { id: 'c', type: 'condition' },
          { id: 'yes', type: 'action', action_name: 'add_label' },
          { id: 'no', type: 'action', action_name: 'remove_label' },
          { id: 'orphan', type: 'action', action_name: 'mute_conversation' },
        ],
        edges: [
          { from: 'n1', to: 'c' },
          { from: 'c', to: 'yes', branch: 'true' },
          { from: 'c', to: 'no', branch: 'false' },
        ],
      };
      const p = computeTreeLayout(definition);
      definition.nodes.forEach(node => {
        expect(p.has(String(node.id))).toBe(true);
        expect(Number.isFinite(p.get(String(node.id)).x)).toBe(true);
        expect(Number.isFinite(p.get(String(node.id)).y)).toBe(true);
      });
      expect(p.size).toBe(definition.nodes.length);
    });

    it('keys the Map by the stringified id (numeric ids)', () => {
      const definition = {
        nodes: [
          { id: 1, type: 'trigger' },
          { id: 2, type: 'action', action_name: 'x' },
        ],
        edges: [{ from: 1, to: 2 }],
      };
      const p = computeTreeLayout(definition);
      expect(p.has('1')).toBe(true);
      expect(p.has('2')).toBe(true);
      // node 2 is still treated as a child (one generation below)
      expect(p.get('2').y).toBe(V_SPACING);
    });

    it('ignores edges that point at a non-existent node', () => {
      const definition = {
        nodes: [{ id: 'n1', type: 'trigger' }],
        edges: [{ from: 'n1', to: 'ghost' }],
      };
      const p = computeTreeLayout(definition);
      expect(p.size).toBe(1);
      expect(p.has('ghost')).toBe(false);
      // with no real children the trigger is treated as a leaf at the origin
      expect(p.get('n1')).toEqual({ x: 0, y: 0 });
    });
  });

  describe('unknown / invalid branch keys', () => {
    it('still places a child whose branch is not a declared port (ranked last)', () => {
      const definition = {
        nodes: [
          { id: 'c', type: 'condition' },
          { id: 'known', type: 'action', action_name: 'x' },
          { id: 'weird', type: 'action', action_name: 'y' },
        ],
        edges: [
          { from: 'c', to: 'weird', branch: 'not-a-real-branch' },
          { from: 'c', to: 'known', branch: 'true' },
        ],
      };
      const p = computeTreeLayout(definition);
      expect(p.has('known')).toBe(true);
      expect(p.has('weird')).toBe(true);
      // the declared 'true' port ranks ahead of the unknown branch
      expect(p.get('known').x).toBeLessThan(p.get('weird').x);
    });
  });

  // ---------------------------------------------------------------------------------------
  // Legibilidade de grafos GRANDES (fluxos reais de menu, ~30 nós). O algoritmo de coluna já
  // era sólido; o que quebrava era (a) tratar todo card como se tivesse a mesma altura, e
  // (b) dar a um nó CONVERGENTE a profundidade do primeiro ramo que o alcançava — o que fazia
  // aresta subir por cima dos cards. Os casos abaixo travam as duas correções.
  // ---------------------------------------------------------------------------------------

  // Retângulo que o card ocupa de fato na tela, com a MESMA estimativa de altura que o layout
  // usa para se espaçar. Bordas encostando não contam como sobreposição (comparação estrita).
  const rectOf = (node, positions) => {
    const { x, y } = positions.get(String(node.id));
    return {
      id: String(node.id),
      left: x,
      right: x + NODE_WIDTH,
      top: y,
      bottom: y + estimateNodeHeight(node),
    };
  };
  const overlappingPairs = definition => {
    const positions = computeTreeLayout(definition);
    const rects = definition.nodes.map(node => rectOf(node, positions));
    const pairs = [];
    rects.forEach((a, i) => {
      rects.slice(i + 1).forEach(b => {
        const hit =
          a.left < b.right &&
          b.left < a.right &&
          a.top < b.bottom &&
          b.top < a.bottom;
        if (hit) pairs.push(`${a.id}↔${b.id}`);
      });
    });
    return pairs;
  };

  // Menu de bot com a forma dos fluxos que quebraram em produção: um wait_for_reply alto (5
  // respostas + timeout + fallback = 7 linhas de porta), submenu, router, e VÁRIOS ramos
  // convergindo no mesmo nó de encerramento — que por isso tem pais em profundidades diferentes.
  const bigMenuFlow = () => ({
    nodes: [
      { id: 'n1', type: 'trigger', event_name: 'conversation_created' },
      { id: 'greet', type: 'action', action_name: 'send_message' },
      {
        id: 'menu',
        type: 'wait_for_reply',
        replies: [
          { key: 'r1' },
          { key: 'r2' },
          { key: 'r3' },
          { key: 'r4' },
          { key: 'r5' },
        ],
        timeout: { enabled: true },
        fallback_key: 'fallback',
      },
      {
        id: 'submenu',
        type: 'wait_for_reply',
        replies: [{ key: 's1' }, { key: 's2' }, { key: 's3' }],
        fallback_key: 'fallback',
      },
      { id: 's1a', type: 'action', action_name: 'assign_team' },
      { id: 's2a', type: 'action', action_name: 'assign_team' },
      { id: 's3a', type: 'action', action_name: 'assign_team' },
      { id: 'sfb', type: 'action', action_name: 'send_message' },
      { id: 'fin', type: 'condition' },
      { id: 'finYes', type: 'action', action_name: 'assign_team' },
      { id: 'finNo', type: 'action', action_name: 'send_message' },
      {
        id: 'router',
        type: 'router',
        routes: [{ key: 'k1' }, { key: 'k2' }, { key: 'k3' }],
        fallback_key: 'fb',
      },
      { id: 'k1a', type: 'action', action_name: 'add_label' },
      { id: 'k2a', type: 'action', action_name: 'add_label' },
      { id: 'k3a', type: 'action', action_name: 'add_label' },
      { id: 'kfba', type: 'action', action_name: 'add_label' },
      { id: 'r4a', type: 'action', action_name: 'mute_conversation' },
      { id: 'r5a', type: 'action', action_name: 'snooze_conversation' },
      { id: 'toa', type: 'action', action_name: 'send_message' },
      { id: 'fba', type: 'action', action_name: 'send_message' },
      { id: 'fim', type: 'action', action_name: 'resolve_conversation' },
    ],
    edges: [
      { from: 'n1', to: 'greet' },
      { from: 'greet', to: 'menu' },
      { from: 'menu', to: 'submenu', branch: 'r1' },
      { from: 'menu', to: 'fin', branch: 'r2' },
      { from: 'menu', to: 'router', branch: 'r3' },
      { from: 'menu', to: 'r4a', branch: 'r4' },
      { from: 'menu', to: 'r5a', branch: 'r5' },
      { from: 'menu', to: 'toa', branch: 'timeout' },
      // fallback do wait_for_reply: aresta SEM branch (contrato com o backend)
      { from: 'menu', to: 'fba' },
      { from: 'submenu', to: 's1a', branch: 's1' },
      { from: 'submenu', to: 's2a', branch: 's2' },
      { from: 'submenu', to: 's3a', branch: 's3' },
      { from: 'submenu', to: 'sfb' },
      { from: 'fin', to: 'finYes', branch: 'true' },
      { from: 'fin', to: 'finNo', branch: 'false' },
      { from: 'router', to: 'k1a', branch: 'k1' },
      { from: 'router', to: 'k2a', branch: 'k2' },
      { from: 'router', to: 'k3a', branch: 'k3' },
      { from: 'router', to: 'kfba', branch: 'fb' },
      // convergência: tudo termina no mesmo nó, a partir de profundidades diferentes
      { from: 's1a', to: 'fim' },
      { from: 's2a', to: 'fim' },
      { from: 's3a', to: 'fim' },
      { from: 'sfb', to: 'fim' },
      { from: 'finYes', to: 'fim' },
      { from: 'finNo', to: 'fim' },
      { from: 'k1a', to: 'fim' },
      { from: 'k2a', to: 'fim' },
      { from: 'k3a', to: 'fim' },
      { from: 'kfba', to: 'fim' },
      { from: 'r4a', to: 'fim' },
      { from: 'r5a', to: 'fim' },
      { from: 'toa', to: 'fim' },
      { from: 'fba', to: 'fim' },
    ],
  });

  describe('estimateNodeHeight', () => {
    it('treats a card without branch ports as the base height', () => {
      const base = estimateNodeHeight({
        id: 'a',
        type: 'action',
        action_name: 'x',
      });
      expect(base).toBeGreaterThan(0);
      expect(estimateNodeHeight({ id: 't', type: 'trigger' })).toBe(base);
    });

    it('grows with every branch port the card renders', () => {
      const base = estimateNodeHeight({ type: 'action', action_name: 'x' });
      const two = estimateNodeHeight({ type: 'condition' });
      const many = estimateNodeHeight({
        type: 'wait_for_reply',
        replies: [{ key: 'a' }, { key: 'b' }, { key: 'c' }],
        timeout: { enabled: true },
      });
      expect(two).toBeGreaterThan(base);
      expect(many).toBeGreaterThan(two);
    });

    it('never returns a non-finite height for a malformed node', () => {
      expect(Number.isFinite(estimateNodeHeight(undefined))).toBe(true);
      expect(Number.isFinite(estimateNodeHeight({ type: 'router' }))).toBe(
        true
      );
      expect(
        Number.isFinite(
          estimateNodeHeight({ type: 'wait_for_reply', replies: 'nope' })
        )
      ).toBe(true);
    });
  });

  describe('no node ever overlaps another', () => {
    it('keeps sibling cards at least one card-width apart', () => {
      const definition = {
        nodes: [
          {
            id: 'r',
            type: 'router',
            routes: [{ key: 'k1' }, { key: 'k2' }, { key: 'k3' }],
            fallback_key: 'fb',
          },
          { id: 'a', type: 'action', action_name: 'x' },
          { id: 'b', type: 'action', action_name: 'y' },
          { id: 'c', type: 'action', action_name: 'z' },
          { id: 'd', type: 'action', action_name: 'w' },
        ],
        edges: [
          { from: 'r', to: 'a', branch: 'k1' },
          { from: 'r', to: 'b', branch: 'k2' },
          { from: 'r', to: 'c', branch: 'k3' },
          { from: 'r', to: 'd', branch: 'fb' },
        ],
      };
      const p = computeTreeLayout(definition);
      const xs = ['a', 'b', 'c', 'd']
        .map(id => p.get(id).x)
        .sort((m, n) => m - n);
      xs.slice(1).forEach((x, i) => {
        expect(x - xs[i]).toBeGreaterThanOrEqual(NODE_WIDTH);
      });
      expect(overlappingPairs(definition)).toEqual([]);
    });

    it('opens the level below a TALL card under its bottom edge, not through it', () => {
      const definition = bigMenuFlow();
      const menu = definition.nodes.find(node => node.id === 'menu');
      // o card do menu é mais alto que o passo fixo antigo — era exatamente a colisão do print
      expect(estimateNodeHeight(menu)).toBeGreaterThan(V_SPACING);
      const p = computeTreeLayout(definition);
      const menuBottom = p.get('menu').y + estimateNodeHeight(menu);
      ['submenu', 'fin', 'router', 'r4a', 'r5a', 'toa', 'fba'].forEach(id => {
        expect(p.get(id).y).toBeGreaterThanOrEqual(menuBottom);
      });
    });

    it('leaves every pair of cards disjoint in a ~20 node menu flow', () => {
      expect(overlappingPairs(bigMenuFlow())).toEqual([]);
    });

    it('leaves every pair of cards disjoint in the small fixtures too', () => {
      expect(
        overlappingPairs({
          nodes: [
            { id: 'n1', type: 'trigger' },
            { id: 'c', type: 'condition' },
            { id: 'yes', type: 'action', action_name: 'add_label' },
            { id: 'no', type: 'action', action_name: 'remove_label' },
            { id: 'orphan', type: 'action', action_name: 'mute_conversation' },
          ],
          edges: [
            { from: 'n1', to: 'c' },
            { from: 'c', to: 'yes', branch: 'true' },
            { from: 'c', to: 'no', branch: 'false' },
          ],
        })
      ).toEqual([]);
    });
  });

  describe('convergent graph — depth is the LONGEST path', () => {
    const definition = {
      nodes: [
        { id: 'n1', type: 'trigger' },
        { id: 'c', type: 'condition' },
        { id: 'long1', type: 'action', action_name: 'a' },
        { id: 'long2', type: 'action', action_name: 'b' },
        { id: 'long3', type: 'action', action_name: 'c' },
        { id: 'end', type: 'action', action_name: 'resolve_conversation' },
      ],
      edges: [
        { from: 'n1', to: 'c' },
        // ramo curto: cai direto no nó compartilhado
        { from: 'c', to: 'end', branch: 'true' },
        // ramo longo: chega no MESMO nó três níveis abaixo
        { from: 'c', to: 'long1', branch: 'false' },
        { from: 'long1', to: 'long2' },
        { from: 'long2', to: 'long3' },
        { from: 'long3', to: 'end' },
      ],
    };

    it('puts the shared node below EVERY one of its parents', () => {
      const p = computeTreeLayout(definition);
      ['c', 'long3'].forEach(parent => {
        expect(p.get('end').y).toBeGreaterThan(p.get(parent).y);
      });
    });

    it('never draws an edge that points upward', () => {
      const flow = bigMenuFlow();
      const p = computeTreeLayout(flow);
      flow.edges.forEach(edge => {
        expect(p.get(String(edge.to)).y).toBeGreaterThan(
          p.get(String(edge.from)).y
        );
      });
    });

    it('still keeps the shared node in a single position (no duplicates)', () => {
      const p = computeTreeLayout(definition);
      expect(p.size).toBe(definition.nodes.length);
    });
  });

  describe('determinism', () => {
    it('returns the same positions for the same definition', () => {
      const a = computeTreeLayout(bigMenuFlow());
      const b = computeTreeLayout(bigMenuFlow());
      expect([...a.entries()]).toEqual([...b.entries()]);
    });
  });
});
