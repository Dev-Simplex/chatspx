import commonHelpers from '../../../../helper/commons';
import getters from '../../conversations/getters';
/*
  Order of conversations in the fixture is as follows:
  - lastActivity: c0 < c3 < c2 < c1
  - createdAt: c3 < c2 < c1 < c0
  - priority: c1 < c2 < c0 < c3
  - waitingSince: c1 > c3 > c0 < c2
*/
import conversations from './conversations.fixtures';

// loads .last() helper
commonHelpers();

describe('#getters', () => {
  describe('#getAllConversations', () => {
    it('returns conversations ordered by lastActivityAt in descending order if no sort order is available', () => {
      const state = { allConversations: [...conversations] };
      expect(getters.getAllConversations(state)).toEqual([
        conversations[1],
        conversations[2],
        conversations[3],
        conversations[0],
      ]);
    });

    it('returns conversations ordered by lastActivityAt in descending order if invalid sort order is available', () => {
      const state = {
        allConversations: [...conversations],
        chatSortFilter: 'latest',
      };
      expect(getters.getAllConversations(state)).toEqual([
        conversations[1],
        conversations[2],
        conversations[3],
        conversations[0],
      ]);
    });

    it('returns conversations ordered by lastActivityAt in descending order if chatStatusFilter = last_activity_at_desc', () => {
      const state = {
        allConversations: [...conversations],
        chatSortFilter: 'last_activity_at_desc',
      };
      expect(getters.getAllConversations(state)).toEqual([
        conversations[1],
        conversations[2],
        conversations[3],
        conversations[0],
      ]);
    });

    it('returns conversations ordered by lastActivityAt in ascending order if chatStatusFilter = last_activity_at_asc', () => {
      const state = {
        allConversations: [...conversations],
        chatSortFilter: 'last_activity_at_asc',
      };
      expect(getters.getAllConversations(state)).toEqual([
        conversations[0],
        conversations[3],
        conversations[2],
        conversations[1],
      ]);
    });

    it('returns conversations ordered by createdAt in descending order if chatStatusFilter = created_at_desc', () => {
      const state = {
        allConversations: [...conversations],
        chatSortFilter: 'created_at_desc',
      };
      expect(getters.getAllConversations(state)).toEqual([
        conversations[0],
        conversations[1],
        conversations[2],
        conversations[3],
      ]);
    });

    it('returns conversations ordered by createdAt in ascending order if chatStatusFilter = created_at_asc', () => {
      const state = {
        allConversations: [...conversations],
        chatSortFilter: 'created_at_asc',
      };
      expect(getters.getAllConversations(state)).toEqual([
        conversations[3],
        conversations[2],
        conversations[1],
        conversations[0],
      ]);
    });

    it('returns conversations ordered by priority in descending order if chatStatusFilter = priority_desc', () => {
      const state = {
        allConversations: [...conversations],
        chatSortFilter: 'priority_desc',
      };
      expect(getters.getAllConversations(state)).toEqual([
        conversations[3],
        conversations[0],
        conversations[1],
        conversations[2],
      ]);
    });

    it('returns conversations ordered by priority in ascending order if chatStatusFilter = priority_asc', () => {
      const state = {
        allConversations: [...conversations],
        chatSortFilter: 'priority_asc',
      };
      expect(getters.getAllConversations(state)).toEqual([
        conversations[1],
        conversations[2],
        conversations[0],
        conversations[3],
      ]);
    });

    it('returns conversations ordered by longest waiting if chatStatusFilter = waiting_since_asc', () => {
      const state = {
        allConversations: [...conversations],
        chatSortFilter: 'waiting_since_asc',
      };
      expect(getters.getAllConversations(state)).toEqual([
        conversations[1],
        conversations[3],
        conversations[2],
        conversations[0],
      ]);
    });
  });
  describe('#getMineChats', () => {
    const buildRootGetters = () => ({
      getCurrentUser: { id: 1 },
      getCurrentAccountId: 1,
      'accounts/getAccount': () => ({ id: 1, settings: {} }),
    });

    it('returns only chats assigned to the current user', () => {
      const conversationList = [
        {
          id: 1,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 1 } },
          labels: [],
        },
        {
          id: 2,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 5 } },
          labels: [],
        },
        { id: 3, inbox_id: 2, status: 1, meta: {}, labels: [] },
      ];

      const result = getters.getMineChats(
        {
          allConversations: conversationList,
          conversationFilters: { status: 1 },
        },
        {},
        {},
        buildRootGetters()
      );
      expect(result.map(c => c.id)).toEqual([1]);
    });

    it('does not include an AI conversation whose mirror bot id collides with the user id', () => {
      const conversationList = [
        {
          id: 1,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 1, type: 'agent_bot' } },
          labels: [],
        },
        {
          id: 2,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 1 } },
          labels: [],
        },
      ];

      const result = getters.getMineChats(
        {
          allConversations: conversationList,
          conversationFilters: { status: 1 },
        },
        {},
        {},
        buildRootGetters()
      );
      expect(result.map(c => c.id)).toEqual([2]);
    });
  });
  describe('#getUnAssignedChats', () => {
    const buildRootGetters = (gateEnabled = false) => ({
      getCurrentAccountId: 1,
      'accounts/getAccount': () => ({
        id: 1,
        settings: { reply_assignment_gate: gateEnabled },
      }),
    });

    it('order returns only chats assigned to user', () => {
      const conversationList = [
        {
          id: 1,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 1 } },
          labels: ['sales', 'dev'],
        },
        {
          id: 2,
          inbox_id: 2,
          status: 1,
          meta: {},
          labels: ['dev'],
        },
        {
          id: 11,
          inbox_id: 3,
          status: 1,
          meta: { assignee: { id: 1 } },
          labels: [],
        },
        {
          id: 22,
          inbox_id: 4,
          status: 1,
          meta: { team: { id: 5 } },
          labels: ['sales'],
        },
      ];

      expect(
        getters.getUnAssignedChats(
          {
            allConversations: conversationList,
            conversationFilters: { status: 1 },
          },
          {},
          {},
          buildRootGetters()
        )
      ).toEqual([
        {
          id: 2,
          inbox_id: 2,
          status: 1,
          meta: {},
          labels: ['dev'],
        },
        {
          id: 22,
          inbox_id: 4,
          status: 1,
          meta: { team: { id: 5 } },
          labels: ['sales'],
        },
      ]);
    });

    it('keeps AI-assigned conversations when the assignment gate is OFF', () => {
      const conversationList = [
        {
          id: 1,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: true } },
          labels: [],
        },
        { id: 2, inbox_id: 2, status: 1, meta: {}, labels: [] },
        {
          id: 3,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 4 } },
          labels: [],
        },
      ];

      const result = getters.getUnAssignedChats(
        {
          allConversations: conversationList,
          conversationFilters: { status: 1 },
        },
        {},
        {},
        buildRootGetters(false)
      );
      expect(result.map(c => c.id).sort()).toEqual([1, 2]);
    });

    it('excludes AI-assigned conversations when the assignment gate is ON', () => {
      const conversationList = [
        {
          id: 1,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: true } },
          labels: [],
        },
        { id: 2, inbox_id: 2, status: 1, meta: {}, labels: [] },
      ];

      const result = getters.getUnAssignedChats(
        {
          allConversations: conversationList,
          conversationFilters: { status: 1 },
        },
        {},
        {},
        buildRootGetters(true)
      );
      expect(result.map(c => c.id)).toEqual([2]);
    });

    it('treats a non-captain (webhook) agent_bot as unassigned even with the gate ON', () => {
      // Backend parity: a webhook bot assigned via column is NOT AI
      // (without_captain_assignee) and still counts as unassigned. It must not
      // be dropped by the gate like a captain mirror is.
      const conversationList = [
        {
          id: 1,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: false } },
          labels: [],
        },
        {
          id: 2,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: true } },
          labels: [],
        },
        { id: 3, inbox_id: 2, status: 1, meta: {}, labels: [] },
      ];

      const result = getters.getUnAssignedChats(
        {
          allConversations: conversationList,
          conversationFilters: { status: 1 },
        },
        {},
        {},
        buildRootGetters(true)
      );
      // Webhook bot (1) stays unassigned; captain mirror (2) is dropped.
      expect(result.map(c => c.id).sort()).toEqual([1, 3]);
    });
  });
  describe('#getAIChats', () => {
    it('returns only conversations assigned to an AI agent (mirror bot)', () => {
      const conversationList = [
        {
          id: 1,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: true } },
          labels: [],
        },
        {
          id: 2,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 4 } },
          labels: [],
        },
        { id: 3, inbox_id: 2, status: 1, meta: {}, labels: [] },
      ];

      const result = getters.getAIChats({
        allConversations: conversationList,
        conversationFilters: { status: 1 },
      });
      expect(result.map(c => c.id)).toEqual([1]);
    });

    it('excludes a non-captain (webhook) agent_bot from the AI tab', () => {
      // Backend parity: only captain mirrors (bot_type = 1) are AI. A webhook
      // bot emits type 'agent_bot' too, but must not surface in the AI tab.
      const conversationList = [
        {
          id: 1,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: true } },
          labels: [],
        },
        {
          id: 2,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 8, type: 'agent_bot', is_captain: false } },
          labels: [],
        },
        {
          id: 3,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 7, type: 'agent_bot' } },
          labels: [],
        },
      ];

      const result = getters.getAIChats({
        allConversations: conversationList,
        conversationFilters: { status: 1 },
      });
      expect(result.map(c => c.id)).toEqual([1]);
    });

    it('applies page filters', () => {
      const conversationList = [
        {
          id: 1,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: true } },
          labels: [],
        },
        {
          id: 2,
          inbox_id: 3,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: true } },
          labels: [],
        },
      ];

      const result = getters.getAIChats({
        allConversations: conversationList,
        conversationFilters: { inboxId: 2, status: 1 },
      });
      expect(result.map(c => c.id)).toEqual([1]);
    });
  });
  describe('#getAwaitingChats', () => {
    it('returns only conversations the AI handed off (aguardando_humano_desde present)', () => {
      // Backend parity (Conversation.awaiting_human / assignee_type=awaiting):
      // the marker presence is the sole criterion — the AI stays the assignee.
      const conversationList = [
        {
          id: 1,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: true } },
          custom_attributes: {
            aguardando_humano_desde: '2026-06-24T10:00:00Z',
          },
          labels: [],
        },
        {
          id: 2,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: true } },
          custom_attributes: {},
          labels: [],
        },
        {
          id: 3,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 4 } },
          labels: [],
        },
      ];

      const result = getters.getAwaitingChats({
        allConversations: conversationList,
        conversationFilters: { status: 1 },
      });
      expect(result.map(c => c.id)).toEqual([1]);
    });

    it('applies page filters', () => {
      const conversationList = [
        {
          id: 1,
          inbox_id: 2,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: true } },
          custom_attributes: {
            aguardando_humano_desde: '2026-06-24T10:00:00Z',
          },
          labels: [],
        },
        {
          id: 2,
          inbox_id: 3,
          status: 1,
          meta: { assignee: { id: 9, type: 'agent_bot', is_captain: true } },
          custom_attributes: {
            aguardando_humano_desde: '2026-06-24T10:00:00Z',
          },
          labels: [],
        },
      ];

      const result = getters.getAwaitingChats({
        allConversations: conversationList,
        conversationFilters: { inboxId: 2, status: 1 },
      });
      expect(result.map(c => c.id)).toEqual([1]);
    });
  });
  describe('#getParticipatingChats', () => {
    const conversationList = [
      { id: 1, inbox_id: 2, status: 1, meta: { assignee: { id: 1 } } },
      { id: 2, inbox_id: 2, status: 1, meta: {} },
      { id: 3, inbox_id: 3, status: 1, meta: { assignee: { id: 2 } } },
    ];

    it('returns all conversations when watchers are not loaded', () => {
      const state = {
        allConversations: conversationList,
        participatingConversationIds: {},
      };
      const rootGetters = {
        getCurrentUser: { id: 1 },
        'conversationWatchers/getByConversationId': () => undefined,
      };
      const result = getters.getParticipatingChats(
        state,
        {},
        {},
        rootGetters
      )({ status: 1 });
      expect(result).toEqual(conversationList);
    });

    it('filters out conversation when watchers loaded and user not participating', () => {
      const state = {
        allConversations: conversationList,
        participatingConversationIds: {},
      };
      const rootGetters = {
        getCurrentUser: { id: 1 },
        'conversationWatchers/getByConversationId': id => {
          if (id === 2) return [{ id: 3 }];
          return undefined;
        },
      };
      const result = getters.getParticipatingChats(
        state,
        {},
        {},
        rootGetters
      )({ status: 1 });
      expect(result).toEqual([conversationList[0], conversationList[2]]);
    });

    it('keeps conversation when watchers loaded and user is participating', () => {
      const state = {
        allConversations: conversationList,
        participatingConversationIds: {},
      };
      const rootGetters = {
        getCurrentUser: { id: 1 },
        'conversationWatchers/getByConversationId': id => {
          if (id === 1) return [{ id: 1 }, { id: 2 }];
          return undefined;
        },
      };
      const result = getters.getParticipatingChats(
        state,
        {},
        {},
        rootGetters
      )({ status: 1 });
      expect(result).toEqual(conversationList);
    });
  });
  describe('#getConversationById', () => {
    it('get conversations based on id', () => {
      const state = {
        allConversations: [
          {
            id: 1,
          },
        ],
      };
      expect(getters.getConversationById(state)(1)).toEqual({ id: 1 });
    });
  });

  describe('#getAppliedConversationFilters', () => {
    it('getAppliedConversationFilters', () => {
      const filtersList = [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: [{ id: 'snoozed', name: 'Snoozed' }],
          query_operator: 'and',
        },
      ];
      const state = {
        appliedFilters: filtersList,
      };
      expect(getters.getAppliedConversationFilters(state)).toEqual(filtersList);
    });
  });

  describe('#getLastEmailInSelectedChat', () => {
    it('Returns cc in last email', () => {
      const state = {};
      const getSelectedChat = {
        messages: [
          {
            message_type: 1,
            content_attributes: {
              email: {
                from: 'why@how.my',
                cc: ['nithin@me.co', 'we@who.why'],
              },
            },
          },
        ],
      };
      expect(
        getters.getLastEmailInSelectedChat(state, { getSelectedChat })
      ).toEqual({
        message_type: 1,
        content_attributes: {
          email: {
            from: 'why@how.my',
            cc: ['nithin@me.co', 'we@who.why'],
          },
        },
      });
    });
  });

  describe('#getSelectedChatAttachments', () => {
    it('Returns attachments in selected chat', () => {
      const attachments = {
        1: [
          { id: 1, file_name: 'test1' },
          { id: 2, file_name: 'test2' },
        ],
      };
      const selectedChatId = 1;
      expect(
        getters.getSelectedChatAttachments({ selectedChatId, attachments })
      ).toEqual([
        { id: 1, file_name: 'test1' },
        { id: 2, file_name: 'test2' },
      ]);
    });
  });

  describe('#getSelectedChatAttachmentsLoaded', () => {
    it('returns true when attachments have been fetched for the selected chat', () => {
      const state = { selectedChatId: 1, attachments: { 1: [] } };
      expect(getters.getSelectedChatAttachmentsLoaded(state)).toBe(true);
    });

    it('returns true when the fetched attachment list is non-empty', () => {
      const state = {
        selectedChatId: 1,
        attachments: { 1: [{ id: 1, file_name: 'test' }] },
      };
      expect(getters.getSelectedChatAttachmentsLoaded(state)).toBe(true);
    });

    it('returns false when attachments have not been fetched yet', () => {
      const state = { selectedChatId: 1, attachments: {} };
      expect(getters.getSelectedChatAttachmentsLoaded(state)).toBe(false);
    });

    it('returns false when no chat is selected', () => {
      const state = { selectedChatId: null, attachments: {} };
      expect(getters.getSelectedChatAttachmentsLoaded(state)).toBe(false);
    });
  });

  describe('#getContextMenuChatId', () => {
    it('returns the context menu chat id', () => {
      const state = { contextMenuChatId: 1 };
      expect(getters.getContextMenuChatId(state)).toEqual(1);
    });
  });

  describe('#getChatListFilters', () => {
    it('get chat list filters', () => {
      const conversationFilters = {
        inboxId: 1,
        assigneeType: 'me',
        status: 'open',
        sortBy: 'created_at',
        page: 1,
        labels: ['label'],
        teamId: 1,
        conversationType: 'mention',
      };
      const state = { conversationFilters: conversationFilters };
      expect(getters.getChatListFilters(state)).toEqual(conversationFilters);
    });
  });

  describe('#getAppliedConversationFiltersQuery', () => {
    it('get applied conversation filters query', () => {
      const filtersList = [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: [{ id: 'snoozed', name: 'Snoozed' }],
          query_operator: 'and',
        },
      ];
      const state = { appliedFilters: filtersList };
      expect(getters.getAppliedConversationFiltersQuery(state)).toEqual({
        payload: [
          {
            attribute_key: 'status',
            filter_operator: 'equal_to',
            query_operator: undefined,
            values: ['snoozed'],
          },
        ],
      });
    });
  });

  describe('#getCopilotAssistant', () => {
    it('get copilot assistant', () => {
      const state = {
        copilotAssistant: {
          id: 1,
          name: 'Assistant',
          description: 'Assistant description',
        },
      };
      expect(getters.getCopilotAssistant(state)).toEqual({
        id: 1,
        name: 'Assistant',
        description: 'Assistant description',
      });
    });
  });

  describe('#getFilteredConversations', () => {
    const mockConversations = [
      {
        id: 1,
        status: 'open',
        meta: { assignee: { id: 1 } },
        last_activity_at: 1000,
      },
      {
        id: 2,
        status: 'open',
        meta: {},
        last_activity_at: 2000,
      },
      {
        id: 3,
        status: 'resolved',
        meta: { assignee: { id: 2 } },
        last_activity_at: 3000,
      },
    ];

    const mockRootGetters = {
      getCurrentUser: {
        id: 1,
        accounts: [{ id: 1, role: 'agent', permissions: [] }],
      },
      getCurrentAccountId: 1,
    };

    it('filters conversations based on role permissions for administrator', () => {
      const state = {
        allConversations: mockConversations,
        chatSortFilter: 'last_activity_at_desc',
        appliedFilters: [],
      };

      const rootGetters = {
        ...mockRootGetters,
        getCurrentUser: {
          ...mockRootGetters.getCurrentUser,
          accounts: [{ id: 1, role: 'administrator', permissions: [] }],
        },
      };

      const result = getters.getFilteredConversations(
        state,
        {},
        {},
        rootGetters
      );

      expect(result).toEqual([
        mockConversations[2],
        mockConversations[1],
        mockConversations[0],
      ]);
    });

    it('filters conversations based on role permissions for agent', () => {
      const state = {
        allConversations: mockConversations,
        chatSortFilter: 'last_activity_at_desc',
        appliedFilters: [],
      };

      const rootGetters = {
        ...mockRootGetters,
        getCurrentUser: {
          ...mockRootGetters.getCurrentUser,
          accounts: [{ id: 1, role: 'agent', permissions: [] }],
        },
      };

      const result = getters.getFilteredConversations(
        state,
        {},
        {},
        rootGetters
      );

      expect(result).toEqual([
        mockConversations[2],
        mockConversations[1],
        mockConversations[0],
      ]);
    });

    it('filters conversations for custom role with conversation_manage permission', () => {
      const state = {
        allConversations: mockConversations,
        chatSortFilter: 'last_activity_at_desc',
        appliedFilters: [],
      };

      const rootGetters = {
        ...mockRootGetters,
        getCurrentUser: {
          ...mockRootGetters.getCurrentUser,
          accounts: [
            {
              id: 1,
              custom_role_id: 5,
              permissions: ['conversation_manage'],
            },
          ],
        },
      };

      const result = getters.getFilteredConversations(
        state,
        {},
        {},
        rootGetters
      );

      expect(result).toEqual([
        mockConversations[2],
        mockConversations[1],
        mockConversations[0],
      ]);
    });

    it('filters conversations for custom role with conversation_unassigned_manage permission', () => {
      const state = {
        allConversations: mockConversations,
        chatSortFilter: 'last_activity_at_desc',
        appliedFilters: [],
      };

      const rootGetters = {
        ...mockRootGetters,
        getCurrentUser: {
          ...mockRootGetters.getCurrentUser,
          accounts: [
            {
              id: 1,
              custom_role_id: 5,
              permissions: ['conversation_unassigned_manage'],
            },
          ],
        },
      };

      const result = getters.getFilteredConversations(
        state,
        {},
        {},
        rootGetters
      );

      // Should include conversation assigned to user (id: 1) and unassigned conversation
      expect(result).toEqual([mockConversations[1], mockConversations[0]]);
    });

    it('filters conversations for custom role with conversation_participating_manage permission', () => {
      const state = {
        allConversations: mockConversations,
        chatSortFilter: 'last_activity_at_desc',
        appliedFilters: [],
      };

      const rootGetters = {
        ...mockRootGetters,
        getCurrentUser: {
          ...mockRootGetters.getCurrentUser,
          accounts: [
            {
              id: 1,
              custom_role_id: 5,
              permissions: ['conversation_participating_manage'],
            },
          ],
        },
      };

      const result = getters.getFilteredConversations(
        state,
        {},
        {},
        rootGetters
      );

      // Should only include conversation assigned to user (id: 1)
      expect(result).toEqual([mockConversations[0]]);
    });

    it('filters conversations for custom role with no permissions', () => {
      const state = {
        allConversations: mockConversations,
        chatSortFilter: 'last_activity_at_desc',
        appliedFilters: [],
      };

      const rootGetters = {
        ...mockRootGetters,
        getCurrentUser: {
          ...mockRootGetters.getCurrentUser,
          accounts: [
            {
              id: 1,
              custom_role_id: 5,
              permissions: [],
            },
          ],
        },
      };

      const result = getters.getFilteredConversations(
        state,
        {},
        {},
        rootGetters
      );

      // Should return empty array as user has no permissions
      expect(result).toEqual([]);
    });

    it('applies filters and role permissions together', () => {
      const state = {
        allConversations: mockConversations,
        chatSortFilter: 'last_activity_at_desc',
        appliedFilters: [
          {
            attribute_key: 'status',
            filter_operator: 'equal_to',
            values: ['open'],
            query_operator: 'and',
          },
        ],
      };

      const rootGetters = {
        ...mockRootGetters,
        getCurrentUser: {
          ...mockRootGetters.getCurrentUser,
          accounts: [
            {
              id: 1,
              custom_role_id: 5,
              permissions: ['conversation_participating_manage'],
            },
          ],
        },
      };

      const result = getters.getFilteredConversations(
        state,
        {},
        {},
        rootGetters
      );

      // Should only include open conversation assigned to user (id: 1)
      expect(result).toEqual([mockConversations[0]]);
    });

    it('returns empty array when no conversations match filters', () => {
      const state = {
        allConversations: mockConversations,
        chatSortFilter: 'last_activity_at_desc',
        appliedFilters: [
          {
            attribute_key: 'status',
            filter_operator: 'equal_to',
            values: ['pending'],
            query_operator: 'and',
          },
        ],
      };

      const result = getters.getFilteredConversations(
        state,
        {},
        {},
        mockRootGetters
      );

      expect(result).toEqual([]);
    });

    it('sorts filtered conversations according to chatSortFilter', () => {
      const state = {
        allConversations: mockConversations,
        chatSortFilter: 'last_activity_at_asc',
        appliedFilters: [],
      };

      const result = getters.getFilteredConversations(
        state,
        {},
        {},
        mockRootGetters
      );

      expect(result).toEqual([
        mockConversations[0],
        mockConversations[1],
        mockConversations[2],
      ]);
    });
  });
});
