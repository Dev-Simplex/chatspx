import axios from 'axios';
import { actions, getters, mutations } from '../../takeoverRequests';
import * as types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');

const record = (over = {}) => ({
  id: 1,
  status: 'pending',
  created_at: 1750000000,
  conversation_id: 5,
  owner: { id: 2, name: 'Ana' },
  requester: { id: 3, name: 'Beto' },
  ...over,
});

describe('takeoverRequests store', () => {
  describe('#actions', () => {
    it('create posts to the conversation-scoped endpoint and stores the result', async () => {
      const commit = vi.fn();
      axios.post.mockResolvedValue({ data: record() });

      await actions.create(
        { commit },
        { conversationId: 5, reason: 'preciso' }
      );

      expect(axios.post).toHaveBeenCalledWith(
        expect.stringContaining('/conversations/5/takeover_requests'),
        { reason: 'preciso' }
      );
      expect(commit).toHaveBeenCalledWith(
        types.default.SET_TAKEOVER_REQUEST,
        record()
      );
    });

    it('create clears the creating flag even when the API fails', async () => {
      const commit = vi.fn();
      axios.post.mockRejectedValue(new Error('boom'));

      await expect(
        actions.create({ commit }, { conversationId: 5 })
      ).rejects.toThrow('boom');

      expect(commit).toHaveBeenCalledWith(
        types.default.SET_TAKEOVER_REQUEST_UI_FLAG,
        {
          isCreating: false,
        }
      );
    });

    it('approve stores the updated record', async () => {
      const commit = vi.fn();
      axios.post.mockResolvedValue({ data: record({ status: 'approved' }) });

      await actions.approve({ commit }, { id: 1, responseNote: 'ok' });

      expect(axios.post).toHaveBeenCalledWith(
        expect.stringContaining('/takeover_requests/1/approve'),
        { response_note: 'ok' }
      );
      expect(commit).toHaveBeenCalledWith(
        types.default.SET_TAKEOVER_REQUEST,
        record({ status: 'approved' })
      );
    });
  });

  describe('#mutations', () => {
    it('camelCases and keys by id', () => {
      const state = { records: {} };
      mutations[types.default.SET_TAKEOVER_REQUEST](state, record());
      expect(state.records[1].conversationId).toBe(5);
      expect(state.records[1].owner.name).toBe('Ana');
    });
  });

  describe('#getters', () => {
    it('getIncoming returns pending requests that have an owner, newest first', () => {
      const state = {
        records: {
          1: { id: 1, status: 'pending', owner: { id: 2 }, createdAt: 100 },
          2: { id: 2, status: 'approved', owner: { id: 2 }, createdAt: 200 },
          3: { id: 3, status: 'pending', owner: { id: 2 }, createdAt: 300 },
        },
      };
      expect(getters.getIncoming(state).map(r => r.id)).toEqual([3, 1]);
    });

    it('getPendingForConversation filters by conversation', () => {
      const state = {
        records: {
          1: { id: 1, status: 'pending', conversationId: 5 },
          2: { id: 2, status: 'pending', conversationId: 9 },
        },
      };
      expect(
        getters
          .getPendingForConversation(state)(5)
          .map(r => r.id)
      ).toEqual([1]);
    });
  });

  // O aviso ao SOLICITANTE quando seu pedido é respondido (o toaster consome).
  describe('#handleRealtimeEvent', () => {
    const rootGetters = { getCurrentUserID: 10 };

    it('notifies the requester when their request is denied', () => {
      const commit = vi.fn();
      const dispatch = vi.fn();
      actions.handleRealtimeEvent(
        { commit, dispatch, rootGetters },
        {
          status: 'denied',
          requester: { id: 10 },
          conversation_id: 5,
          response_note: 'agora não',
        }
      );

      expect(dispatch).toHaveBeenCalledWith('fetchIncoming');
      expect(commit).toHaveBeenCalledWith(
        types.default.SET_TAKEOVER_RESOLVED_NOTICE,
        { status: 'denied', conversationId: 5, note: 'agora não' }
      );
    });

    it('notifies the requester when their request is approved', () => {
      const commit = vi.fn();
      actions.handleRealtimeEvent(
        { commit, dispatch: vi.fn(), rootGetters },
        { status: 'approved', requester: { id: 10 }, conversation_id: 5 }
      );
      expect(commit).toHaveBeenCalledWith(
        types.default.SET_TAKEOVER_RESOLVED_NOTICE,
        { status: 'approved', conversationId: 5, note: null }
      );
    });

    // O DONO (não sou o solicitante) só refaz a lista — sem toast de resolução.
    it('does NOT set a notice for someone who is not the requester', () => {
      const commit = vi.fn();
      const dispatch = vi.fn();
      actions.handleRealtimeEvent(
        { commit, dispatch, rootGetters },
        { status: 'denied', requester: { id: 99 }, conversation_id: 5 }
      );

      expect(dispatch).toHaveBeenCalledWith('fetchIncoming');
      expect(commit).not.toHaveBeenCalled();
    });

    // Pedido só CRIADO (pending) não é resolução — nada de toast.
    it('does NOT set a notice for a pending (created) event', () => {
      const commit = vi.fn();
      actions.handleRealtimeEvent(
        { commit, dispatch: vi.fn(), rootGetters },
        { status: 'pending', requester: { id: 10 }, conversation_id: 5 }
      );
      expect(commit).not.toHaveBeenCalled();
    });
  });
});
