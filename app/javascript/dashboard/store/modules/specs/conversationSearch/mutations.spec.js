import types from '../../../mutation-types';
import { mutations } from '../../conversationSearch';

describe('#mutations', () => {
  describe('#SEARCH_CONVERSATIONS_SET', () => {
    it('set records correctly', () => {
      const state = { records: [] };
      mutations[types.SEARCH_CONVERSATIONS_SET](state, [{ id: 1 }]);
      expect(state.records).toEqual([{ id: 1 }]);
    });
  });

  describe('#SEARCH_CONVERSATIONS_SET_UI_FLAG', () => {
    it('set uiFlags correctly', () => {
      const state = { uiFlags: { isFetching: true } };
      mutations[types.SEARCH_CONVERSATIONS_SET_UI_FLAG](state, {
        isFetching: false,
      });
      expect(state.uiFlags).toEqual({ isFetching: false });
    });
  });

  describe('#CONTACT_SEARCH_SET', () => {
    it('should append new contact records to existing ones', () => {
      const state = { contactRecords: [{ id: 1 }] };
      mutations[types.CONTACT_SEARCH_SET](state, [{ id: 2 }]);
      expect(state.contactRecords).toEqual([{ id: 1 }, { id: 2 }]);
    });
  });

  describe('#CONVERSATION_SEARCH_SET', () => {
    it('should replace conversation records', () => {
      const state = { conversationRecords: [{ id: 1 }] };
      mutations[types.CONVERSATION_SEARCH_SET](state, [{ id: 2 }]);
      expect(state.conversationRecords).toEqual([{ id: 2 }]);
    });
  });

  describe('#CONVERSATION_SEARCH_SET_IF_CURRENT', () => {
    it('should set conversation records when requestId matches', () => {
      const state = {
        lastConversationSearchRequestId: 100,
        conversationRecords: [],
      };
      mutations[types.CONVERSATION_SEARCH_SET_IF_CURRENT](state, {
        requestId: 100,
        records: [{ id: 1 }],
      });
      expect(state.conversationRecords).toEqual([{ id: 1 }]);
    });

    it('should not set conversation records when requestId does not match', () => {
      const state = {
        lastConversationSearchRequestId: 100,
        conversationRecords: [{ id: 1 }],
      };
      mutations[types.CONVERSATION_SEARCH_SET_IF_CURRENT](state, {
        requestId: 99,
        records: [{ id: 2 }],
      });
      expect(state.conversationRecords).toEqual([{ id: 1 }]);
    });
  });

  describe('#SET_CONVERSATION_SEARCH_REQUEST_ID', () => {
    it('should set lastConversationSearchRequestId', () => {
      const state = { lastConversationSearchRequestId: null };
      mutations[types.SET_CONVERSATION_SEARCH_REQUEST_ID](state, 123);
      expect(state.lastConversationSearchRequestId).toBe(123);
    });
  });

  describe('#MESSAGE_SEARCH_SET', () => {
    it('should append new message records to existing ones', () => {
      const state = { messageRecords: [{ id: 1 }] };
      mutations[types.MESSAGE_SEARCH_SET](state, [{ id: 2 }]);
      expect(state.messageRecords).toEqual([{ id: 1 }, { id: 2 }]);
    });
  });

  describe('#FULL_SEARCH_SET_UI_FLAG', () => {
    it('set full search UI flags correctly', () => {
      const state = {
        uiFlags: {
          isFetching: true,
          isSearchCompleted: false,
        },
      };
      mutations[types.FULL_SEARCH_SET_UI_FLAG](state, {
        isFetching: false,
        isSearchCompleted: true,
      });
      expect(state.uiFlags).toEqual({
        isFetching: false,
        isSearchCompleted: true,
      });
    });
  });

  describe('#CONTACT_SEARCH_SET_UI_FLAG', () => {
    it('set contact search UI flags correctly', () => {
      const state = {
        uiFlags: {
          contact: { isFetching: true },
        },
      };
      mutations[types.CONTACT_SEARCH_SET_UI_FLAG](state, { isFetching: false });
      expect(state.uiFlags.contact).toEqual({ isFetching: false });
    });
  });

  describe('#CONVERSATION_SEARCH_SET_UI_FLAG', () => {
    it('set conversation search UI flags correctly', () => {
      const state = {
        uiFlags: {
          conversation: { isFetching: true },
        },
      };
      mutations[types.CONVERSATION_SEARCH_SET_UI_FLAG](state, {
        isFetching: false,
      });
      expect(state.uiFlags.conversation).toEqual({ isFetching: false });
    });
  });

  describe('#MESSAGE_SEARCH_SET_UI_FLAG', () => {
    it('set message search UI flags correctly', () => {
      const state = {
        uiFlags: {
          message: { isFetching: true },
        },
      };
      mutations[types.MESSAGE_SEARCH_SET_UI_FLAG](state, { isFetching: false });
      expect(state.uiFlags.message).toEqual({ isFetching: false });
    });
  });

  describe('#ARTICLE_SEARCH_SET', () => {
    it('should append new article records to existing ones', () => {
      const state = { articleRecords: [{ id: 1 }] };
      mutations[types.ARTICLE_SEARCH_SET](state, [{ id: 2 }]);
      expect(state.articleRecords).toEqual([{ id: 1 }, { id: 2 }]);
    });
  });

  describe('#ARTICLE_SEARCH_SET_UI_FLAG', () => {
    it('set article search UI flags correctly', () => {
      const state = {
        uiFlags: {
          article: { isFetching: true },
        },
      };
      mutations[types.ARTICLE_SEARCH_SET_UI_FLAG](state, { isFetching: false });
      expect(state.uiFlags.article).toEqual({ isFetching: false });
    });
  });

  describe('#SET_CONVERSATION_SEARCH_QUERY', () => {
    it('should set conversation search query', () => {
      const state = { conversationSearchQuery: '' };
      mutations[types.SET_CONVERSATION_SEARCH_QUERY](state, 'leo');
      expect(state.conversationSearchQuery).toBe('leo');
    });
    it('should set empty string when query is falsy', () => {
      const state = { conversationSearchQuery: 'leo' };
      mutations[types.SET_CONVERSATION_SEARCH_QUERY](state, '');
      expect(state.conversationSearchQuery).toBe('');
    });
  });

  describe('#SET_CONVERSATION_SEARCH_COMPLETED', () => {
    it('should set conversation search completed flag', () => {
      const state = { conversationSearchCompleted: false };
      mutations[types.SET_CONVERSATION_SEARCH_COMPLETED](state, true);
      expect(state.conversationSearchCompleted).toBe(true);
    });
    it('should set false when value is falsy', () => {
      const state = { conversationSearchCompleted: true };
      mutations[types.SET_CONVERSATION_SEARCH_COMPLETED](state, false);
      expect(state.conversationSearchCompleted).toBe(false);
    });
  });

  describe('#CLEAR_SEARCH_RESULTS', () => {
    it('should clear all search records and request id', () => {
      const state = {
        contactRecords: [{ id: 1 }],
        conversationRecords: [{ id: 1 }],
        lastConversationSearchRequestId: 123,
        conversationSearchQuery: 'test',
        conversationSearchCompleted: true,
        messageRecords: [{ id: 1 }],
        articleRecords: [{ id: 1 }],
      };
      mutations[types.CLEAR_SEARCH_RESULTS](state);
      expect(state.contactRecords).toEqual([]);
      expect(state.conversationRecords).toEqual([]);
      expect(state.lastConversationSearchRequestId).toBeNull();
      expect(state.conversationSearchQuery).toBe('');
      expect(state.conversationSearchCompleted).toBe(false);
      expect(state.messageRecords).toEqual([]);
      expect(state.articleRecords).toEqual([]);
    });
  });
});
