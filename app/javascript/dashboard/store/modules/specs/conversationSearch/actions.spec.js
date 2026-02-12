import { actions } from '../../conversationSearch';
import types from '../../../mutation-types';
import axios from 'axios';

const commit = vi.fn();
const dispatch = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  beforeEach(() => {
    commit.mockClear();
    dispatch.mockClear();
    axios.get.mockClear();
  });

  describe('#get', () => {
    it('sends correct actions if no query param is provided', () => {
      actions.get({ commit }, { q: '' });
      expect(commit.mock.calls).toEqual([[types.SEARCH_CONVERSATIONS_SET, []]]);
    });

    it('sends correct actions if query param is provided and API call is success', async () => {
      axios.get.mockResolvedValue({
        data: {
          payload: [{ messages: [{ id: 1, content: 'value testing' }], id: 1 }],
        },
      });

      await actions.get({ commit }, { q: 'value' });
      expect(commit.mock.calls).toEqual([
        [types.SEARCH_CONVERSATIONS_SET, []],
        [types.SEARCH_CONVERSATIONS_SET_UI_FLAG, { isFetching: true }],
        [
          types.SEARCH_CONVERSATIONS_SET,
          [{ messages: [{ id: 1, content: 'value testing' }], id: 1 }],
        ],
        [types.SEARCH_CONVERSATIONS_SET_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('sends correct actions if query param is provided and API call is errored', async () => {
      axios.get.mockRejectedValue({});
      await actions.get({ commit }, { q: 'value' });
      expect(commit.mock.calls).toEqual([
        [types.SEARCH_CONVERSATIONS_SET, []],
        [types.SEARCH_CONVERSATIONS_SET_UI_FLAG, { isFetching: true }],
        [types.SEARCH_CONVERSATIONS_SET_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#fullSearch', () => {
    it('should not dispatch any actions if no query provided', async () => {
      await actions.fullSearch({ commit, dispatch }, { q: '' });
      expect(dispatch).not.toHaveBeenCalled();
    });

    it('should dispatch all search actions and set UI flags correctly', async () => {
      await actions.fullSearch({ commit, dispatch }, { q: 'test' });

      expect(commit.mock.calls).toEqual([
        [
          types.FULL_SEARCH_SET_UI_FLAG,
          { isFetching: true, isSearchCompleted: false },
        ],
        [
          types.FULL_SEARCH_SET_UI_FLAG,
          { isFetching: false, isSearchCompleted: true },
        ],
      ]);

      expect(dispatch).toHaveBeenCalledWith('contactSearch', { q: 'test' });
      expect(dispatch).toHaveBeenCalledWith('conversationSearch', {
        q: 'test',
      });
      expect(dispatch).toHaveBeenCalledWith('messageSearch', { q: 'test' });
      expect(dispatch).toHaveBeenCalledWith('articleSearch', { q: 'test' });
    });

    it('should pass filters to all search actions including articleSearch', async () => {
      const payload = { q: 'test', since: 1700000000, until: 1732000000 };
      await actions.fullSearch({ commit, dispatch }, payload);

      expect(dispatch).toHaveBeenCalledWith('contactSearch', payload);
      expect(dispatch).toHaveBeenCalledWith('conversationSearch', payload);
      expect(dispatch).toHaveBeenCalledWith('messageSearch', payload);
      expect(dispatch).toHaveBeenCalledWith('articleSearch', payload);
    });
  });

  describe('#contactSearch', () => {
    it('should handle successful contact search', async () => {
      axios.get.mockResolvedValue({
        data: { payload: { contacts: [{ id: 1 }] } },
      });

      await actions.contactSearch({ commit }, { q: 'test', page: 1 });
      expect(commit.mock.calls).toEqual([
        [types.CONTACT_SEARCH_SET_UI_FLAG, { isFetching: true }],
        [types.CONTACT_SEARCH_SET, [{ id: 1 }]],
        [types.CONTACT_SEARCH_SET_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('should handle failed contact search', async () => {
      axios.get.mockRejectedValue({});
      await actions.contactSearch({ commit }, { q: 'test' });
      expect(commit.mock.calls).toEqual([
        [types.CONTACT_SEARCH_SET_UI_FLAG, { isFetching: true }],
        [types.CONTACT_SEARCH_SET_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#conversationSearch', () => {
    it('should handle successful conversation search', async () => {
      axios.get.mockResolvedValue({
        data: { payload: { conversations: [{ id: 1 }] } },
      });

      await actions.conversationSearch({ commit }, { q: 'test', page: 1 });
      expect(commit.mock.calls.length).toBe(4);
      expect(commit.mock.calls[0][0]).toBe(types.SET_CONVERSATION_SEARCH_REQUEST_ID);
      expect(commit.mock.calls[0][1]).toEqual(expect.any(Number));
      expect(commit.mock.calls[1]).toEqual([
        types.CONVERSATION_SEARCH_SET_UI_FLAG,
        { isFetching: true },
      ]);
      expect(commit.mock.calls[2][0]).toBe(types.CONVERSATION_SEARCH_SET_IF_CURRENT);
      expect(commit.mock.calls[2][1]).toMatchObject({
        requestId: expect.any(Number),
        records: expect.any(Array),
      });
      expect(commit.mock.calls[2][1].records.length).toBe(1);
      expect(commit.mock.calls[2][1].records[0]).toMatchObject({ id: 1 });
      expect(commit.mock.calls[3]).toEqual([
        types.CONVERSATION_SEARCH_SET_UI_FLAG,
        { isFetching: false },
      ]);
    });

    it('should handle failed conversation search', async () => {
      axios.get.mockRejectedValue({});
      await actions.conversationSearch({ commit }, { q: 'test' });
      expect(commit.mock.calls.length).toBe(3);
      expect(commit.mock.calls[0][0]).toBe(types.SET_CONVERSATION_SEARCH_REQUEST_ID);
      expect(commit.mock.calls[1]).toEqual([
        types.CONVERSATION_SEARCH_SET_UI_FLAG,
        { isFetching: true },
      ]);
      expect(commit.mock.calls[2]).toEqual([
        types.CONVERSATION_SEARCH_SET_UI_FLAG,
        { isFetching: false },
      ]);
    });

    it('should not log error on AbortError', async () => {
      const abortError = new Error('Aborted');
      abortError.name = 'AbortError';
      axios.get.mockRejectedValue(abortError);
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      await actions.conversationSearch({ commit }, { q: 'test' });
      expect(consoleSpy).not.toHaveBeenCalled();
      consoleSpy.mockRestore();
    });
  });

  describe('#messageSearch', () => {
    it('should handle successful message search', async () => {
      axios.get.mockResolvedValue({
        data: { payload: { messages: [{ id: 1 }] } },
      });

      await actions.messageSearch({ commit }, { q: 'test', page: 1 });
      expect(commit.mock.calls).toEqual([
        [types.MESSAGE_SEARCH_SET_UI_FLAG, { isFetching: true }],
        [types.MESSAGE_SEARCH_SET, [{ id: 1 }]],
        [types.MESSAGE_SEARCH_SET_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('should handle failed message search', async () => {
      axios.get.mockRejectedValue({});
      await actions.messageSearch({ commit }, { q: 'test' });
      expect(commit.mock.calls).toEqual([
        [types.MESSAGE_SEARCH_SET_UI_FLAG, { isFetching: true }],
        [types.MESSAGE_SEARCH_SET_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#articleSearch', () => {
    it('should handle successful article search', async () => {
      axios.get.mockResolvedValue({
        data: { payload: { articles: [{ id: 1 }] } },
      });

      await actions.articleSearch({ commit }, { q: 'test', page: 1 });
      expect(commit.mock.calls).toEqual([
        [types.ARTICLE_SEARCH_SET_UI_FLAG, { isFetching: true }],
        [types.ARTICLE_SEARCH_SET, [{ id: 1 }]],
        [types.ARTICLE_SEARCH_SET_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('should handle article search with date filters', async () => {
      axios.get.mockResolvedValue({
        data: { payload: { articles: [{ id: 1 }] } },
      });

      await actions.articleSearch(
        { commit },
        { q: 'test', page: 1, since: 1700000000, until: 1732000000 }
      );
      expect(commit.mock.calls).toEqual([
        [types.ARTICLE_SEARCH_SET_UI_FLAG, { isFetching: true }],
        [types.ARTICLE_SEARCH_SET, [{ id: 1 }]],
        [types.ARTICLE_SEARCH_SET_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('should handle failed article search', async () => {
      axios.get.mockRejectedValue({});
      await actions.articleSearch({ commit }, { q: 'test' });
      expect(commit.mock.calls).toEqual([
        [types.ARTICLE_SEARCH_SET_UI_FLAG, { isFetching: true }],
        [types.ARTICLE_SEARCH_SET_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#clearSearchResults', () => {
    it('should commit clear search results mutation', () => {
      actions.clearSearchResults({ commit });
      expect(commit).toHaveBeenCalledWith(types.CLEAR_SEARCH_RESULTS);
    });
  });
});
