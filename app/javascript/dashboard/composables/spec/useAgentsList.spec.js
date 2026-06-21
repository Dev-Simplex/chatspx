import { ref } from 'vue';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useAgentsList } from '../useAgentsList';
import { useMapGetter } from 'dashboard/composables/store';
import { useReplyAssignmentGate } from 'dashboard/composables/useReplyAssignmentGate';
import { allAgentsData, formattedAgentsData } from './fixtures/agentFixtures';
import * as agentHelper from 'dashboard/helper/agentHelper';

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => (key === 'AGENT_MGMT.MULTI_SELECTOR.LIST.NONE' ? 'None' : key),
  }),
}));

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useReplyAssignmentGate');
vi.mock('dashboard/helper/agentHelper');

// Create a mock None agent
const mockNoneAgent = {
  confirmed: true,
  name: 'None',
  id: 0,
  role: 'agent',
  account_id: 0,
  email: 'None',
};

const mockUseMapGetter = (overrides = {}) => {
  const defaultGetters = {
    getCurrentUser: ref(allAgentsData[0]),
    getSelectedChat: ref({ inbox_id: 1, meta: { assignee: true } }),
    getCurrentAccountId: ref(1),
    'inboxAssignableAgents/getAssignableAgents': ref(() => allAgentsData),
  };

  const mergedGetters = { ...defaultGetters, ...overrides };

  useMapGetter.mockImplementation(getter => mergedGetters[getter]);
};

describe('useAgentsList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    agentHelper.getAgentsByUpdatedPresence.mockImplementation(agents => agents);
    agentHelper.getSortedAgentsByAvailability.mockReturnValue(
      formattedAgentsData.slice(1)
    );
    useReplyAssignmentGate.mockReturnValue({
      isAssignmentGateEnabled: ref(false),
    });

    mockUseMapGetter();
  });

  it('returns agentsList and assignableAgents', () => {
    const { agentsList, assignableAgents } = useAgentsList();

    expect(assignableAgents.value).toEqual(allAgentsData);
    expect(agentsList.value[0]).toEqual(mockNoneAgent);
    expect(agentsList.value.length).toBe(
      formattedAgentsData.slice(1).length + 1
    );
  });

  it('includes None agent when includeNoneAgent is true', () => {
    const { agentsList } = useAgentsList(true);

    expect(agentsList.value[0]).toEqual(mockNoneAgent);
    expect(agentsList.value.length).toBe(
      formattedAgentsData.slice(1).length + 1
    );
  });

  it('excludes None agent when includeNoneAgent is false', () => {
    const { agentsList } = useAgentsList(false);

    expect(agentsList.value[0].id).not.toBe(0);
    expect(agentsList.value.length).toBe(formattedAgentsData.slice(1).length);
  });

  it('handles empty assignable agents', () => {
    mockUseMapGetter({
      'inboxAssignableAgents/getAssignableAgents': ref(() => []),
    });
    agentHelper.getSortedAgentsByAvailability.mockReturnValue([]);

    const { agentsList, assignableAgents } = useAgentsList();

    expect(assignableAgents.value).toEqual([]);
    expect(agentsList.value).toEqual([mockNoneAgent]);
  });

  it('handles missing inbox_id', () => {
    mockUseMapGetter({
      getSelectedChat: ref({ meta: { assignee: true } }),
      'inboxAssignableAgents/getAssignableAgents': ref(() => []),
    });
    agentHelper.getSortedAgentsByAvailability.mockReturnValue([]);

    const { agentsList, assignableAgents } = useAgentsList();

    expect(assignableAgents.value).toEqual([]);
    expect(agentsList.value).toEqual([mockNoneAgent]);
  });

  describe('reply assignment gate (D-11)', () => {
    it('does not inject None when the gate is enabled, even with an assignee', () => {
      useReplyAssignmentGate.mockReturnValue({
        isAssignmentGateEnabled: ref(true),
      });

      const { agentsList } = useAgentsList(true);

      expect(agentsList.value.find(agent => agent.id === 0)).toBeUndefined();
      expect(agentsList.value.length).toBe(formattedAgentsData.slice(1).length);
    });

    it('injects None when the gate is disabled and an assignee is selected', () => {
      useReplyAssignmentGate.mockReturnValue({
        isAssignmentGateEnabled: ref(false),
      });

      const { agentsList } = useAgentsList(true);

      expect(agentsList.value[0]).toEqual(mockNoneAgent);
    });

    it('does not inject None with gate disabled when there is no assignee', () => {
      mockUseMapGetter({
        getSelectedChat: ref({ inbox_id: 1, meta: { assignee: null } }),
      });

      const { agentsList } = useAgentsList(true);

      expect(agentsList.value.find(agent => agent.id === 0)).toBeUndefined();
    });
  });
});
