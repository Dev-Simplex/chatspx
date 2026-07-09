import { computeTreeLayout, H_SPACING, V_SPACING } from '../flowLayout';

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
});
