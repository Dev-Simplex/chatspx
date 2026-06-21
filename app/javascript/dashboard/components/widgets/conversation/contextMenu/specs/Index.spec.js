import { describe, it, expect } from 'vitest';
import ContextMenu from '../Index.vue';

const { computed } = ContextMenu;

const agents = [
  { id: 1, name: 'Paulo', role: 'agent' },
  { id: 2, name: 'Maria', role: 'administrator' },
];

const buildVm = ({ gateEnabled }) => ({
  isAssignmentGateEnabled: gateEnabled,
  filteredAgentOnAvailability: agents,
  $t: key => key,
});

describe('conversation contextMenu assignableAgents', () => {
  it('omits the None option when the assignment gate is ON (D-11)', () => {
    const result = computed.assignableAgents.call(
      buildVm({ gateEnabled: true })
    );

    expect(result).toEqual(agents);
    expect(result.find(agent => agent.id === null)).toBeUndefined();
  });

  it('keeps an i18n-ized None option when the assignment gate is OFF', () => {
    const result = computed.assignableAgents.call(
      buildVm({ gateEnabled: false })
    );

    expect(result).toHaveLength(agents.length + 1);
    expect(result[0]).toMatchObject({
      id: null,
      // i18n-izado: resolve pela chave, não pelo hardcode 'None'
      name: 'AGENT_MGMT.MULTI_SELECTOR.LIST.NONE',
    });
    expect(result.slice(1)).toEqual(agents);
  });
});
