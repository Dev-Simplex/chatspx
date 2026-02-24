import { ref } from 'vue';
import { useBulkActions } from '../useBulkActions';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useResolveValidation } from 'dashboard/composables/useResolveValidation';
import { useI18n } from 'vue-i18n';

vi.mock('vuex', () => ({
  useStore: vi.fn(),
}));
vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: vi.fn(),
}));
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));
vi.mock('dashboard/composables/useResolveValidation', () => ({
  useResolveValidation: vi.fn(),
}));
vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(),
}));

describe('useBulkActions', () => {
  let store;
  let selectedConversations;
  let conversationsById;

  beforeEach(() => {
    conversationsById = {};
    store = {
      dispatch: vi.fn(),
      getters: {
        'conversations/getConversationById': vi.fn(id => conversationsById[id]),
      },
    };

    selectedConversations = ref([101, 102]);

    useStore.mockReturnValue(store);
    useMapGetter.mockImplementation(getter => {
      if (getter === 'bulkActions/getSelectedConversationIds') {
        return selectedConversations;
      }
      return ref(null);
    });
    useI18n.mockReturnValue({
      t: vi.fn(key => key),
    });
    useResolveValidation.mockReturnValue({
      showTeamModal: ref(false),
      teams: ref([{ id: 9, name: 'Support' }]),
      validateAndResolveBulk: vi.fn(),
      assignTeamAndResolve: vi.fn(),
      cancelTeamSelection: vi.fn(),
    });
  });

  it('assigns agent directly when conversation already has team', async () => {
    const { onAssignAgent, showTransferTeamModal } = useBulkActions();

    conversationsById[205] = {
      id: 205,
      meta: { team: { id: 1, name: 'Support' } },
    };
    await onAssignAgent({ id: 7, name: 'Agent 7' }, [205]);

    expect(showTransferTeamModal.value).toBe(false);
    expect(store.dispatch).toHaveBeenNthCalledWith(1, 'bulkActions/process', {
      type: 'Conversation',
      ids: [205],
      fields: {
        assignee_id: 7,
      },
    });
    expect(store.dispatch).toHaveBeenNthCalledWith(
      2,
      'bulkActions/clearSelectedConversationIds'
    );
  });

  it('opens team modal and applies team then assignee when conversation has no team', async () => {
    const { onAssignAgent, onConfirmAgentTransferTeam, showTransferTeamModal } =
      useBulkActions();

    conversationsById[206] = {
      id: 206,
      meta: { team: null },
      team_id: null,
    };
    await onAssignAgent({ id: 7, name: 'Agent 7' }, [206]);

    expect(showTransferTeamModal.value).toBe(true);
    await onConfirmAgentTransferTeam(9);

    expect(store.dispatch).toHaveBeenNthCalledWith(1, 'bulkActions/process', {
      type: 'Conversation',
      ids: [206],
      fields: {
        team_id: 9,
      },
    });
    expect(store.dispatch).toHaveBeenNthCalledWith(2, 'bulkActions/process', {
      type: 'Conversation',
      ids: [206],
      fields: {
        assignee_id: 7,
      },
    });
    expect(store.dispatch).toHaveBeenNthCalledWith(
      3,
      'bulkActions/clearSelectedConversationIds'
    );
    expect(showTransferTeamModal.value).toBe(false);
  });

  it('applies selected team only to conversations without team in bulk mixed transfer', async () => {
    const { onAssignAgent, onConfirmAgentTransferTeam, showTransferTeamModal } =
      useBulkActions();

    selectedConversations.value = [101, 102, 103];
    conversationsById[101] = {
      id: 101,
      meta: { team: { id: 1, name: 'Sales' } },
    };
    conversationsById[102] = {
      id: 102,
      meta: { team: null },
      team_id: null,
    };

    await onAssignAgent({ id: 7, name: 'Agent 7' });
    expect(showTransferTeamModal.value).toBe(true);

    await onConfirmAgentTransferTeam(9);

    expect(store.dispatch).toHaveBeenNthCalledWith(1, 'bulkActions/process', {
      type: 'Conversation',
      ids: [102, 103],
      fields: {
        team_id: 9,
      },
    });
    expect(store.dispatch).toHaveBeenNthCalledWith(2, 'bulkActions/process', {
      type: 'Conversation',
      ids: [101, 102, 103],
      fields: {
        assignee_id: 7,
      },
    });
    expect(store.dispatch).toHaveBeenNthCalledWith(
      3,
      'bulkActions/clearSelectedConversationIds'
    );
  });

  it('does not update conversations when transfer is canceled', async () => {
    const {
      onAssignAgent,
      cancelAgentTransferTeamSelection,
      onConfirmAgentTransferTeam,
    } = useBulkActions();

    await onAssignAgent({ id: 7, name: 'Agent 7' });
    cancelAgentTransferTeamSelection();
    await onConfirmAgentTransferTeam(9);

    expect(store.dispatch).not.toHaveBeenCalled();
  });

  it('keeps unassign flow without team modal', async () => {
    const { onAssignAgent, showTransferTeamModal } = useBulkActions();

    await onAssignAgent({ id: 0, name: 'None' }, [205]);

    expect(showTransferTeamModal.value).toBe(false);
    expect(store.dispatch).toHaveBeenNthCalledWith(1, 'bulkActions/process', {
      type: 'Conversation',
      ids: [205],
      fields: {
        assignee_id: 0,
      },
    });
  });
});
