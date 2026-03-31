import types from '../mutation-types';
import { debounce } from '@chatwoot/utils';

import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

const persistDrafts = debounce(records => {
  LocalStorage.set(LOCAL_STORAGE_KEYS.DRAFT_MESSAGES, records);
}, 1000);

const state = {
  records: LocalStorage.get(LOCAL_STORAGE_KEYS.DRAFT_MESSAGES) || {},
  replyEditorMode: REPLY_EDITOR_MODES.REPLY,
};

export const getters = {
  get: _state => key => {
    return _state.records[key] || '';
  },
  getReplyEditorMode: _state => _state.replyEditorMode,
};

export const actions = {
  set: async ({ commit }, { key, message }) => {
    commit(types.SET_DRAFT_MESSAGES, { key, message });
  },
  delete: ({ commit }, { key }) => {
    commit(types.REMOVE_DRAFT_MESSAGES, { key });
  },
  setReplyEditorMode: ({ commit }, { mode }) => {
    commit(types.SET_REPLY_EDITOR_MODE, { mode });
  },
};

export const mutations = {
  [types.SET_DRAFT_MESSAGES]($state, { key, message }) {
    $state.records = {
      ...$state.records,
      [key]: message,
    };
    persistDrafts($state.records);
  },
  [types.REMOVE_DRAFT_MESSAGES]($state, { key }) {
    const { [key]: draftToBeRemoved, ...updatedRecords } = $state.records;
    $state.records = updatedRecords;
    persistDrafts($state.records);
  },
  [types.SET_REPLY_EDITOR_MODE]($state, { mode }) {
    $state.replyEditorMode = mode;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
