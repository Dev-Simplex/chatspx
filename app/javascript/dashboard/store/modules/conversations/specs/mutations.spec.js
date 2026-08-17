import { mutations } from '../index';
import types from '../../../mutation-types';

const buildStateWithChat = chat => {
  const state = {
    allConversations: [chat],
    conversationMap: { [chat.id]: chat },
    selectedChatId: null,
  };
  return state;
};

describe('#mutations', () => {
  describe('#ADD_MESSAGE order preservation', () => {
    it('inserts out-of-order message at correct chronological position', () => {
      const chat = {
        id: 1,
        messages: [
          { id: 100, created_at: 1700000000 },
          { id: 200, created_at: 1750000000 },
          { id: 300, created_at: 1778025000 },
        ],
        hasNewerMessages: false,
      };
      const state = buildStateWithChat(chat);

      mutations[types.ADD_MESSAGE](state, {
        id: 150,
        conversation_id: 1,
        created_at: 1740000000,
      });

      const ids = state.allConversations[0].messages.map(m => m.id);
      expect(ids).toEqual([100, 150, 200, 300]);
    });

    it('appends to end when message is the newest', () => {
      const chat = {
        id: 1,
        messages: [
          { id: 100, created_at: 1700000000 },
          { id: 200, created_at: 1750000000 },
        ],
        hasNewerMessages: false,
      };
      const state = buildStateWithChat(chat);

      mutations[types.ADD_MESSAGE](state, {
        id: 300,
        conversation_id: 1,
        created_at: 1780000000,
      });

      const ids = state.allConversations[0].messages.map(m => m.id);
      expect(ids).toEqual([100, 200, 300]);
    });

    it('prepends when message is the oldest', () => {
      const chat = {
        id: 1,
        messages: [
          { id: 200, created_at: 1750000000 },
          { id: 300, created_at: 1780000000 },
        ],
        hasNewerMessages: false,
      };
      const state = buildStateWithChat(chat);

      mutations[types.ADD_MESSAGE](state, {
        id: 100,
        conversation_id: 1,
        created_at: 1700000000,
      });

      const ids = state.allConversations[0].messages.map(m => m.id);
      expect(ids).toEqual([100, 200, 300]);
    });

    it('reproduces Tozi scenario: out-of-order push from WAHA status sync stays sorted', () => {
      // Simulates Bug 1 (06-mai-2026): array has today's messages, status sync
      // re-emits a message from 11-abril → must be inserted at position, not appended.
      const today = 1778025000;
      const aprilEleven = 1744300000;
      const chat = {
        id: 1177,
        messages: [
          { id: 9001, created_at: today - 7200 },
          { id: 9002, created_at: today - 3600 },
          { id: 9003, created_at: today },
        ],
        hasNewerMessages: false,
      };
      const state = buildStateWithChat(chat);

      mutations[types.ADD_MESSAGE](state, {
        id: 5500,
        conversation_id: 1177,
        created_at: aprilEleven,
        status: 'delivered',
      });

      const messages = state.allConversations[0].messages;
      const timestamps = messages.map(m => m.created_at);
      const sorted = [...timestamps].sort((a, b) => a - b);
      expect(timestamps).toEqual(sorted);
      expect(messages[0].id).toBe(5500);
    });

    it('replaces existing message in place when id matches (preserves order)', () => {
      const chat = {
        id: 1,
        messages: [
          { id: 100, created_at: 1700000000, status: 'sent' },
          { id: 200, created_at: 1750000000, status: 'sent' },
          { id: 300, created_at: 1780000000, status: 'sent' },
        ],
        hasNewerMessages: false,
      };
      const state = buildStateWithChat(chat);

      mutations[types.ADD_MESSAGE](state, {
        id: 200,
        conversation_id: 1,
        created_at: 1750000000,
        status: 'delivered',
      });

      const messages = state.allConversations[0].messages;
      expect(messages.map(m => m.id)).toEqual([100, 200, 300]);
      expect(messages[1].status).toBe('delivered');
    });

    it('handles empty messages array (push)', () => {
      const chat = {
        id: 1,
        messages: [],
        hasNewerMessages: false,
      };
      const state = buildStateWithChat(chat);

      mutations[types.ADD_MESSAGE](state, {
        id: 100,
        conversation_id: 1,
        created_at: 1700000000,
      });

      expect(state.allConversations[0].messages).toHaveLength(1);
      expect(state.allConversations[0].messages[0].id).toBe(100);
    });

    it('does not inject when hasNewerMessages is true (user browsing history)', () => {
      const chat = {
        id: 1,
        messages: [
          { id: 100, created_at: 1700000000 },
          { id: 200, created_at: 1750000000 },
        ],
        hasNewerMessages: true,
        pendingNewMessageCount: 0,
      };
      const state = buildStateWithChat(chat);

      mutations[types.ADD_MESSAGE](state, {
        id: 300,
        conversation_id: 1,
        created_at: 1780000000,
      });

      expect(state.allConversations[0].messages.map(m => m.id)).toEqual([
        100, 200,
      ]);
      expect(state.allConversations[0].pendingNewMessageCount).toBe(1);
    });
  });

  describe('#UPDATE_CONVERSATION_CALL_STATUS', () => {
    it('does nothing if conversation is not found', () => {
      const state = { allConversations: [] };
      mutations[types.UPDATE_CONVERSATION_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'ringing',
      });
      expect(state.allConversations).toEqual([]);
    });

    it('updates call_status preserving existing additional_attributes', () => {
      const state = {
        allConversations: [
          { id: 1, additional_attributes: { other_attr: 'value' } },
        ],
      };
      mutations[types.UPDATE_CONVERSATION_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'in-progress',
      });
      expect(state.allConversations[0].additional_attributes).toEqual({
        other_attr: 'value',
        call_status: 'in-progress',
      });
    });

    it('creates additional_attributes if it does not exist', () => {
      const state = { allConversations: [{ id: 1 }] };
      mutations[types.UPDATE_CONVERSATION_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'completed',
      });
      expect(state.allConversations[0].additional_attributes).toEqual({
        call_status: 'completed',
      });
    });
  });

  describe('#UPDATE_MESSAGE_CALL_STATUS', () => {
    it('does nothing if conversation is not found', () => {
      const state = { allConversations: [] };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'ringing',
      });
      expect(state.allConversations).toEqual([]);
    });

    it('does nothing if no voice call message exists', () => {
      const state = {
        allConversations: [
          { id: 1, messages: [{ id: 1, content_type: 'text' }] },
        ],
      };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'ringing',
      });
      expect(state.allConversations[0].messages[0]).toEqual({
        id: 1,
        content_type: 'text',
      });
    });

    it('updates the last voice call message status', () => {
      const state = {
        allConversations: [
          {
            id: 1,
            messages: [
              {
                id: 1,
                content_type: 'voice_call',
                content_attributes: { data: { status: 'ringing' } },
              },
              {
                id: 2,
                content_type: 'voice_call',
                content_attributes: { data: { status: 'ringing' } },
              },
            ],
          },
        ],
      };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'in-progress',
      });
      expect(
        state.allConversations[0].messages[0].content_attributes.data.status
      ).toBe('ringing');
      expect(
        state.allConversations[0].messages[1].content_attributes.data.status
      ).toBe('in-progress');
    });

    it('creates content_attributes.data if it does not exist', () => {
      const state = {
        allConversations: [
          {
            id: 1,
            messages: [{ id: 1, content_type: 'voice_call' }],
          },
        ],
      };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'completed',
      });
      expect(
        state.allConversations[0].messages[0].content_attributes.data.status
      ).toBe('completed');
    });

    it('preserves existing data in content_attributes.data', () => {
      const state = {
        allConversations: [
          {
            id: 1,
            messages: [
              {
                id: 1,
                content_type: 'voice_call',
                content_attributes: {
                  data: { call_sid: 'CA123', status: 'ringing' },
                },
              },
            ],
          },
        ],
      };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'in-progress',
      });
      expect(
        state.allConversations[0].messages[0].content_attributes.data
      ).toEqual({
        call_sid: 'CA123',
        status: 'in-progress',
      });
    });

    it('handles empty messages array', () => {
      const state = {
        allConversations: [{ id: 1, messages: [] }],
      };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'ringing',
      });
      expect(state.allConversations[0].messages).toEqual([]);
    });
  });

  describe('#REMOVE_OPTIMISTIC_MESSAGE', () => {
    it('removes only the still-optimistic message (id === echo_id)', () => {
      const chat = {
        id: 1,
        messages: [
          // optimistic placeholder still keyed by echo_id
          { id: 'uuid-abc', echo_id: 'uuid-abc', content: 'hi' },
          // server copy of the same message (numeric id, echo_id persisted)
          {
            id: 999,
            content: 'hi',
            additional_attributes: { echo_id: 'uuid-abc' },
          },
        ],
      };
      const state = buildStateWithChat(chat);

      mutations[types.REMOVE_OPTIMISTIC_MESSAGE](state, {
        conversationId: 1,
        echoId: 'uuid-abc',
      });

      const { messages } = state.allConversations[0];
      expect(messages).toHaveLength(1);
      expect(messages[0].id).toBe(999);
    });

    it('does not touch a reconciled message that shares the echo_id', () => {
      const chat = {
        id: 1,
        messages: [
          { id: 999, echo_id: 'uuid-abc', content: 'already reconciled' },
        ],
      };
      const state = buildStateWithChat(chat);

      mutations[types.REMOVE_OPTIMISTIC_MESSAGE](state, {
        conversationId: 1,
        echoId: 'uuid-abc',
      });

      expect(state.allConversations[0].messages).toHaveLength(1);
    });
  });

  describe('#SET/CLEAR_CONVERSATION_ACCESS_BLOCKED', () => {
    it('stores the block meta by conversation id', () => {
      const state = { accessBlocked: {} };
      mutations[types.SET_CONVERSATION_ACCESS_BLOCKED](state, {
        id: 7,
        meta: { current_assignee: { id: 3, name: 'Ana' } },
      });
      expect(state.accessBlocked[7].current_assignee.name).toBe('Ana');
    });

    it('defaults the meta to an empty object', () => {
      const state = { accessBlocked: {} };
      mutations[types.SET_CONVERSATION_ACCESS_BLOCKED](state, { id: 7 });
      expect(state.accessBlocked[7]).toEqual({});
    });

    it('clears the block for a conversation', () => {
      const state = { accessBlocked: { 7: { foo: 1 }, 9: { bar: 2 } } };
      mutations[types.CLEAR_CONVERSATION_ACCESS_BLOCKED](state, 7);
      expect(state.accessBlocked[7]).toBeUndefined();
      expect(state.accessBlocked[9]).toBeDefined();
    });

    it('is a no-op clearing an id that is not blocked', () => {
      const state = { accessBlocked: { 9: { bar: 2 } } };
      const before = state.accessBlocked;
      mutations[types.CLEAR_CONVERSATION_ACCESS_BLOCKED](state, 7);
      expect(state.accessBlocked).toBe(before);
    });
  });
});
