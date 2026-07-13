import {
  FAMILIES,
  PALETTE_SECTIONS,
  NODE_CATALOG,
  familyForNode,
  labelForNode,
  iconForNode,
  catalogEntryForNode,
} from '../nodeCatalog';

const VALID_TYPES = [
  'trigger',
  'action',
  'condition',
  'router',
  'wait',
  'wait_for_reply',
];

// Builds a definition node that should resolve to the given catalog item.
const nodeFor = item =>
  item.type === 'action'
    ? { type: 'action', action_name: item.actionName }
    : { type: item.type };

describe('nodeCatalog — structure', () => {
  describe('FAMILIES', () => {
    it('defines the six design-system families', () => {
      expect(Object.keys(FAMILIES).sort()).toEqual(
        ['action', 'ai', 'data', 'logic', 'msg', 'trigger'].sort()
      );
    });

    it('gives every family a labelKey plus light/dark colors', () => {
      Object.values(FAMILIES).forEach(family => {
        expect(typeof family.labelKey).toBe('string');
        expect(family.labelKey.length).toBeGreaterThan(0);
        expect(family.color).toMatch(/^#[0-9a-f]{6}$/i);
        expect(family.colorDark).toMatch(/^#[0-9a-f]{6}$/i);
      });
    });
  });

  describe('PALETTE_SECTIONS', () => {
    it('maps one-to-one onto the families', () => {
      const sectionFamilies = PALETTE_SECTIONS.map(
        section => section.family
      ).sort();
      expect(sectionFamilies).toEqual(Object.keys(FAMILIES).sort());
    });

    it('gives every section a valid family and a labelKey', () => {
      PALETTE_SECTIONS.forEach(section => {
        expect(FAMILIES).toHaveProperty(section.family);
        expect(typeof section.labelKey).toBe('string');
        expect(section.labelKey.length).toBeGreaterThan(0);
      });
    });
  });

  describe('NODE_CATALOG', () => {
    it('gives every item a key, a valid type, a valid family, a labelKey and an icon', () => {
      NODE_CATALOG.forEach(item => {
        expect(typeof item.key).toBe('string');
        expect(item.key.length).toBeGreaterThan(0);
        expect(VALID_TYPES).toContain(item.type);
        expect(FAMILIES).toHaveProperty(item.family);
        expect(item.labelKey).toMatch(/^AUTOMATION\.CANVAS\.NODES\./);
        expect(typeof item.icon).toBe('string');
        expect(item.icon.length).toBeGreaterThan(0);
      });
    });

    it('has no duplicate keys', () => {
      const keys = NODE_CATALOG.map(item => item.key);
      expect(new Set(keys).size).toBe(keys.length);
    });

    it('has no duplicate labelKeys', () => {
      const labelKeys = NODE_CATALOG.map(item => item.labelKey);
      expect(new Set(labelKeys).size).toBe(labelKeys.length);
    });

    it('gives every action item a unique actionName', () => {
      const actionNames = NODE_CATALOG.filter(
        item => item.type === 'action'
      ).map(item => item.actionName);
      expect(actionNames.every(Boolean)).toBe(true);
      expect(new Set(actionNames).size).toBe(actionNames.length);
    });

    it('gives non-action items no actionName', () => {
      NODE_CATALOG.filter(item => item.type !== 'action').forEach(item => {
        expect(item.actionName).toBeUndefined();
      });
    });
  });
});

describe('catalogEntryForNode', () => {
  it('returns null for a nullish node', () => {
    expect(catalogEntryForNode(null)).toBeNull();
    expect(catalogEntryForNode(undefined)).toBeNull();
  });

  it('matches an action node by action_name', () => {
    const entry = catalogEntryForNode({
      type: 'action',
      action_name: 'send_message',
    });
    expect(entry).toMatchObject({
      key: 'send_message',
      actionName: 'send_message',
      family: 'msg',
    });
  });

  it('returns null for an action with an unknown action_name', () => {
    expect(
      catalogEntryForNode({ type: 'action', action_name: 'does_not_exist' })
    ).toBeNull();
  });

  it('matches non-action nodes by type', () => {
    expect(catalogEntryForNode({ type: 'trigger' }).key).toBe('trigger');
    expect(catalogEntryForNode({ type: 'condition' }).key).toBe('condition');
    expect(catalogEntryForNode({ type: 'router' }).key).toBe('router');
    expect(catalogEntryForNode({ type: 'wait' }).key).toBe('wait');
    expect(catalogEntryForNode({ type: 'wait_for_reply' }).key).toBe(
      'wait_for_reply'
    );
  });

  it('returns null for an unknown node type', () => {
    expect(catalogEntryForNode({ type: 'mystery' })).toBeNull();
  });
});

describe('familyForNode', () => {
  it('defaults to "action" for a nullish node', () => {
    expect(familyForNode(null)).toBe('action');
    expect(familyForNode(undefined)).toBe('action');
  });

  it('resolves the family of a known action', () => {
    expect(
      familyForNode({ type: 'action', action_name: 'assign_ai_agent' })
    ).toBe('ai');
    expect(familyForNode({ type: 'action', action_name: 'send_message' })).toBe(
      'msg'
    );
    expect(familyForNode({ type: 'action', action_name: 'http_request' })).toBe(
      'data'
    );
  });

  it('falls back to "action" for an unknown action', () => {
    expect(
      familyForNode({ type: 'action', action_name: 'unknown_action' })
    ).toBe('action');
  });

  it('resolves the logic family for condition / router / wait / wait_for_reply', () => {
    expect(familyForNode({ type: 'condition' })).toBe('logic');
    expect(familyForNode({ type: 'router' })).toBe('logic');
    expect(familyForNode({ type: 'wait' })).toBe('logic');
    expect(familyForNode({ type: 'wait_for_reply' })).toBe('logic');
  });

  it('resolves the trigger family for a trigger node', () => {
    expect(familyForNode({ type: 'trigger' })).toBe('trigger');
  });

  it('falls back to "logic" for an unknown non-action type', () => {
    expect(familyForNode({ type: 'mystery' })).toBe('logic');
  });
});

describe('labelForNode', () => {
  it('returns an empty string for a nullish node', () => {
    expect(labelForNode(null)).toBe('');
    expect(labelForNode(undefined)).toBe('');
  });

  it('returns the i18n labelKey of a known node', () => {
    expect(labelForNode({ type: 'action', action_name: 'send_message' })).toBe(
      'AUTOMATION.CANVAS.NODES.SEND_MESSAGE'
    );
    expect(labelForNode({ type: 'trigger' })).toBe(
      'AUTOMATION.CANVAS.NODES.TRIGGER'
    );
  });

  it('falls back to the raw action_name for an unknown action', () => {
    expect(labelForNode({ type: 'action', action_name: 'custom_thing' })).toBe(
      'custom_thing'
    );
  });

  it('falls back to the raw type for an unknown non-action node', () => {
    expect(labelForNode({ type: 'mystery' })).toBe('mystery');
  });

  it('returns an empty string for a node with neither a known entry nor type/action_name', () => {
    expect(labelForNode({})).toBe('');
  });
});

describe('iconForNode', () => {
  it('returns the lucide icon of a known node', () => {
    expect(iconForNode({ type: 'action', action_name: 'send_message' })).toBe(
      'i-lucide-message-square'
    );
    expect(iconForNode({ type: 'trigger' })).toBe('i-lucide-zap');
  });

  it('falls back to a generic square icon for unknown / null nodes', () => {
    expect(iconForNode({ type: 'action', action_name: 'nope' })).toBe(
      'i-lucide-square'
    );
    expect(iconForNode({ type: 'mystery' })).toBe('i-lucide-square');
    expect(iconForNode(null)).toBe('i-lucide-square');
  });
});

describe('send_interactive node (F1 WhatsApp interactive)', () => {
  const node = { type: 'action', action_name: 'send_interactive' };

  it('is registered in the catalog under the msg family', () => {
    const entry = NODE_CATALOG.find(item => item.key === 'send_interactive');
    expect(entry).toMatchObject({
      key: 'send_interactive',
      type: 'action',
      actionName: 'send_interactive',
      family: 'msg',
      labelKey: 'AUTOMATION.CANVAS.NODES.SEND_INTERACTIVE',
      icon: 'i-lucide-list',
    });
  });

  it('resolves via catalogEntryForNode by action_name', () => {
    expect(catalogEntryForNode(node)).toMatchObject({
      key: 'send_interactive',
      actionName: 'send_interactive',
      family: 'msg',
    });
  });

  it('resolves the msg family via familyForNode', () => {
    expect(familyForNode(node)).toBe('msg');
  });

  it('resolves the i18n labelKey via labelForNode', () => {
    expect(labelForNode(node)).toBe('AUTOMATION.CANVAS.NODES.SEND_INTERACTIVE');
  });

  it('resolves the list icon via iconForNode', () => {
    expect(iconForNode(node)).toBe('i-lucide-list');
  });
});

describe('wait_for_reply node (F2 branch-on-reply)', () => {
  const node = { type: 'wait_for_reply' };

  it('is registered in the catalog under the logic family', () => {
    const entry = NODE_CATALOG.find(item => item.key === 'wait_for_reply');
    expect(entry).toMatchObject({
      key: 'wait_for_reply',
      type: 'wait_for_reply',
      family: 'logic',
      labelKey: 'AUTOMATION.CANVAS.NODES.WAIT_FOR_REPLY',
      icon: 'i-lucide-messages-square',
    });
  });

  it('has no actionName (it is a type node, not an action)', () => {
    const entry = NODE_CATALOG.find(item => item.key === 'wait_for_reply');
    expect(entry.actionName).toBeUndefined();
  });

  it('resolves via catalogEntryForNode by type', () => {
    expect(catalogEntryForNode(node)).toMatchObject({
      key: 'wait_for_reply',
      type: 'wait_for_reply',
      family: 'logic',
    });
  });

  it('resolves the logic family via familyForNode', () => {
    expect(familyForNode(node)).toBe('logic');
  });

  it('resolves the i18n labelKey via labelForNode', () => {
    expect(labelForNode(node)).toBe('AUTOMATION.CANVAS.NODES.WAIT_FOR_REPLY');
  });

  it('resolves the messages icon via iconForNode', () => {
    expect(iconForNode(node)).toBe('i-lucide-messages-square');
  });
});

describe('send_cta_url node (F3 WhatsApp link button)', () => {
  const node = { type: 'action', action_name: 'send_cta_url' };

  it('is registered in the catalog under the msg family', () => {
    const entry = NODE_CATALOG.find(item => item.key === 'send_cta_url');
    expect(entry).toMatchObject({
      key: 'send_cta_url',
      type: 'action',
      actionName: 'send_cta_url',
      family: 'msg',
      labelKey: 'AUTOMATION.CANVAS.NODES.SEND_CTA_URL',
      icon: 'i-lucide-external-link',
    });
  });

  it('resolves via catalogEntryForNode by action_name', () => {
    expect(catalogEntryForNode(node)).toMatchObject({
      key: 'send_cta_url',
      actionName: 'send_cta_url',
      family: 'msg',
    });
  });

  it('resolves the msg family via familyForNode', () => {
    expect(familyForNode(node)).toBe('msg');
  });

  it('resolves the i18n labelKey via labelForNode', () => {
    expect(labelForNode(node)).toBe('AUTOMATION.CANVAS.NODES.SEND_CTA_URL');
  });

  it('resolves the external-link icon via iconForNode', () => {
    expect(iconForNode(node)).toBe('i-lucide-external-link');
  });
});

describe('send_location_request node (F3 WhatsApp location request)', () => {
  const node = { type: 'action', action_name: 'send_location_request' };

  it('is registered in the catalog under the msg family', () => {
    const entry = NODE_CATALOG.find(
      item => item.key === 'send_location_request'
    );
    expect(entry).toMatchObject({
      key: 'send_location_request',
      type: 'action',
      actionName: 'send_location_request',
      family: 'msg',
      labelKey: 'AUTOMATION.CANVAS.NODES.SEND_LOCATION_REQUEST',
      icon: 'i-lucide-map-pin',
    });
  });

  it('resolves via catalogEntryForNode by action_name', () => {
    expect(catalogEntryForNode(node)).toMatchObject({
      key: 'send_location_request',
      actionName: 'send_location_request',
      family: 'msg',
    });
  });

  it('resolves the msg family via familyForNode', () => {
    expect(familyForNode(node)).toBe('msg');
  });

  it('resolves the i18n labelKey via labelForNode', () => {
    expect(labelForNode(node)).toBe(
      'AUTOMATION.CANVAS.NODES.SEND_LOCATION_REQUEST'
    );
  });

  it('resolves the map-pin icon via iconForNode', () => {
    expect(iconForNode(node)).toBe('i-lucide-map-pin');
  });
});

describe('send_whatsapp_flow node (F3 native WhatsApp Flow form)', () => {
  const node = { type: 'action', action_name: 'send_whatsapp_flow' };

  it('is registered in the catalog under the msg family', () => {
    const entry = NODE_CATALOG.find(item => item.key === 'send_whatsapp_flow');
    expect(entry).toMatchObject({
      key: 'send_whatsapp_flow',
      type: 'action',
      actionName: 'send_whatsapp_flow',
      family: 'msg',
      labelKey: 'AUTOMATION.CANVAS.NODES.SEND_WHATSAPP_FLOW',
      icon: 'i-lucide-clipboard-list',
    });
  });

  it('resolves via catalogEntryForNode by action_name', () => {
    expect(catalogEntryForNode(node)).toMatchObject({
      key: 'send_whatsapp_flow',
      actionName: 'send_whatsapp_flow',
      family: 'msg',
    });
  });

  it('resolves the msg family via familyForNode', () => {
    expect(familyForNode(node)).toBe('msg');
  });

  it('resolves the i18n labelKey via labelForNode', () => {
    expect(labelForNode(node)).toBe(
      'AUTOMATION.CANVAS.NODES.SEND_WHATSAPP_FLOW'
    );
  });

  it('resolves the clipboard-list icon via iconForNode', () => {
    expect(iconForNode(node)).toBe('i-lucide-clipboard-list');
  });
});

describe('catalog <-> resolver consistency', () => {
  it('familyForNode round-trips every catalog item', () => {
    NODE_CATALOG.forEach(item => {
      expect(familyForNode(nodeFor(item))).toBe(item.family);
    });
  });

  it('labelForNode round-trips every catalog item', () => {
    NODE_CATALOG.forEach(item => {
      expect(labelForNode(nodeFor(item))).toBe(item.labelKey);
    });
  });

  it('iconForNode round-trips every catalog item', () => {
    NODE_CATALOG.forEach(item => {
      expect(iconForNode(nodeFor(item))).toBe(item.icon);
    });
  });
});
