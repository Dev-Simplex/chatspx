import SearchAPI from '../../api/search';
import types from '../mutation-types';
export const initialState = {
  records: [],
  contactRecords: [],
  conversationRecords: [],
  messageRecords: [],
  articleRecords: [],
  uiFlags: {
    isFetching: false,
    isSearchCompleted: false,
    contact: { isFetching: false },
    conversation: { isFetching: false },
    message: { isFetching: false },
    article: { isFetching: false },
  },
};

export const getters = {
  getConversations(state) {
    return state.records;
  },
  getContactRecords(state) {
    return state.contactRecords;
  },
  getConversationRecords(state) {
    return state.conversationRecords;
  },
  getMessageRecords(state) {
    return state.messageRecords;
  },
  getArticleRecords(state) {
    return state.articleRecords;
  },
  getUIFlags(state) {
    return state.uiFlags;
  },
};

export const actions = {
  async get({ commit }, { q }) {
    commit(types.SEARCH_CONVERSATIONS_SET, []);
    if (!q) {
      return;
    }
    commit(types.SEARCH_CONVERSATIONS_SET_UI_FLAG, { isFetching: true });
    try {
      const {
        data: { payload },
      } = await SearchAPI.get({ q });
      commit(types.SEARCH_CONVERSATIONS_SET, payload);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.SEARCH_CONVERSATIONS_SET_UI_FLAG, {
        isFetching: false,
      });
    }
  },
  async fullSearch({ commit, dispatch }, payload) {
    const { q, ...filters } = payload;
    if (!q && !Object.keys(filters).length) {
      return;
    }
    commit(types.FULL_SEARCH_SET_UI_FLAG, {
      isFetching: true,
      isSearchCompleted: false,
    });
    try {
      await Promise.all([
        dispatch('contactSearch', { q, ...filters }),
        dispatch('conversationSearch', { q, ...filters }),
        dispatch('messageSearch', { q, ...filters }),
        dispatch('articleSearch', { q, ...filters }),
      ]);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.FULL_SEARCH_SET_UI_FLAG, {
        isFetching: false,
        isSearchCompleted: true,
      });
    }
  },
  async contactSearch({ commit }, payload) {
    const { page = 1, ...searchParams } = payload;
    commit(types.CONTACT_SEARCH_SET_UI_FLAG, { isFetching: true });
    try {
      const { data } = await SearchAPI.contacts({ ...searchParams, page });
      commit(types.CONTACT_SEARCH_SET, data.payload.contacts);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.CONTACT_SEARCH_SET_UI_FLAG, { isFetching: false });
    }
  },
  async conversationSearch({ commit, rootGetters }, payload) {
    const { page = 1, ...searchParams } = payload;
    commit(types.CONVERSATION_SEARCH_SET_UI_FLAG, { isFetching: true });
    try {
      const { data } = await SearchAPI.conversations({ ...searchParams, page });
      const conversations = data.payload.conversations || [];
      
      // Normalizar dados para garantir estrutura igual à lista normal
      const enrichedConversations = conversations.map(conv => {
        const normalized = { ...conv };
        
        // Flatten meta - copiar campos importantes para o nível superior
        if (normalized.meta) {
          // Contact (prioridade: meta.contact > meta.sender)
          if (!normalized.contact) {
            normalized.contact = normalized.meta.contact || normalized.meta.sender;
          }
          
          // Sender
          if (!normalized.sender && normalized.meta.sender) {
            normalized.sender = normalized.meta.sender;
          }
          
          // Mensagens - copiar todos os campos de mensagem
          if (!normalized.last_message && normalized.meta.last_message) {
            normalized.last_message = normalized.meta.last_message;
          }
          if (!normalized.last_non_activity_message && normalized.meta.last_non_activity_message) {
            normalized.last_non_activity_message = normalized.meta.last_non_activity_message;
          }
          if (!normalized.last_activity_message && normalized.meta.last_activity_message) {
            normalized.last_activity_message = normalized.meta.last_activity_message;
          }
        }
        
        // Garantir que contact existe e tem estrutura completa
        const contactSource = normalized.contact || normalized.sender || normalized.meta?.contact || normalized.meta?.sender;
        if (contactSource) {
          normalized.contact = {
            id: contactSource.id || null,
            name: contactSource.name || contactSource.full_name || 'Unknown',
            thumbnail: contactSource.thumbnail || contactSource.avatar_url || contactSource.avatar || contactSource.profile_image_url || '',
            availability_status: contactSource.availability_status || 'offline',
            ...contactSource, // Manter outros campos
          };
          
          // Tentar enriquecer com dados da store se tiver ID e não tiver thumbnail
          if (normalized.contact.id && !normalized.contact.thumbnail && rootGetters['contacts/getContact']) {
            const storeContact = rootGetters['contacts/getContact'](normalized.contact.id);
            if (storeContact && storeContact.thumbnail) {
              normalized.contact.thumbnail = storeContact.thumbnail;
            }
            if (storeContact && storeContact.name && !normalized.contact.name) {
              normalized.contact.name = storeContact.name;
            }
          }
        }
        
        return normalized;
      });
      
      commit(types.CONVERSATION_SEARCH_SET, enrichedConversations);
    } catch (error) {
      console.error('[conversationSearch] Erro:', error);
    } finally {
      commit(types.CONVERSATION_SEARCH_SET_UI_FLAG, { isFetching: false });
    }
  },
  async messageSearch({ commit }, payload) {
    const { page = 1, ...searchParams } = payload;
    commit(types.MESSAGE_SEARCH_SET_UI_FLAG, { isFetching: true });
    try {
      const { data } = await SearchAPI.messages({ ...searchParams, page });
      commit(types.MESSAGE_SEARCH_SET, data.payload.messages);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.MESSAGE_SEARCH_SET_UI_FLAG, { isFetching: false });
    }
  },
  // Search messages within a specific conversation
  async messageSearchInConversation({ commit }, { q, conversation_id, page = 1 }) {
    // Always clear previous results when starting a new search in conversation
    commit(types.CLEAR_MESSAGE_SEARCH_RESULTS);
    commit(types.MESSAGE_SEARCH_SET_UI_FLAG, { isFetching: true });
    try {
      const { data } = await SearchAPI.messages({ q, page, conversation_id });
      const messages = data.payload.messages || [];
      // Replace results instead of appending
      commit(types.MESSAGE_SEARCH_SET_REPLACE, messages);
    } catch (error) {
      console.error('[messageSearchInConversation] Erro:', error);
    } finally {
      commit(types.MESSAGE_SEARCH_SET_UI_FLAG, { isFetching: false });
    }
  },
  async articleSearch({ commit }, payload) {
    const { page = 1, ...searchParams } = payload;
    commit(types.ARTICLE_SEARCH_SET_UI_FLAG, { isFetching: true });
    try {
      const { data } = await SearchAPI.articles({ ...searchParams, page });
      commit(types.ARTICLE_SEARCH_SET, data.payload.articles);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.ARTICLE_SEARCH_SET_UI_FLAG, { isFetching: false });
    }
  },
  async clearSearchResults({ commit }) {
    commit(types.CLEAR_SEARCH_RESULTS);
  },
};

export const mutations = {
  [types.SEARCH_CONVERSATIONS_SET](state, records) {
    state.records = records;
  },
  [types.CONTACT_SEARCH_SET](state, records) {
    state.contactRecords = [...state.contactRecords, ...records];
  },
  [types.CONVERSATION_SEARCH_SET](state, records) {
    // Os dados já vêm normalizados e enriquecidos da action
    state.conversationRecords = records || [];
  },
  [types.MESSAGE_SEARCH_SET](state, records) {
    state.messageRecords = [...state.messageRecords, ...records];
  },
  [types.MESSAGE_SEARCH_SET_REPLACE](state, records) {
    state.messageRecords = records || [];
  },
  [types.CLEAR_MESSAGE_SEARCH_RESULTS](state) {
    state.messageRecords = [];
  },
  [types.ARTICLE_SEARCH_SET](state, records) {
    state.articleRecords = [...state.articleRecords, ...records];
  },
  [types.SEARCH_CONVERSATIONS_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags = { ...state.uiFlags, ...uiFlags };
  },
  [types.FULL_SEARCH_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags = { ...state.uiFlags, ...uiFlags };
  },
  [types.CONTACT_SEARCH_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags.contact = { ...state.uiFlags.contact, ...uiFlags };
  },
  [types.CONVERSATION_SEARCH_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags.conversation = { ...state.uiFlags.conversation, ...uiFlags };
  },
  [types.MESSAGE_SEARCH_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags.message = { ...state.uiFlags.message, ...uiFlags };
  },
  [types.ARTICLE_SEARCH_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags.article = { ...state.uiFlags.article, ...uiFlags };
  },
  [types.CLEAR_SEARCH_RESULTS](state) {
    state.contactRecords = [];
    state.conversationRecords = [];
    state.messageRecords = [];
    state.articleRecords = [];
  },
};

export default {
  namespaced: true,
  state: initialState,
  getters,
  actions,
  mutations,
};
