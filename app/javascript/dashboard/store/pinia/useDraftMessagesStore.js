import { defineStore, acceptHMRUpdate } from 'pinia';
import { debounce } from '@chatwoot/utils';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

// Espelho Pinia de store/modules/draftMessages.js (Onda 2 P0-05).
const persistDrafts = debounce(records => {
  LocalStorage.set(LOCAL_STORAGE_KEYS.DRAFT_MESSAGES, records);
}, 1000);

export const useDraftMessagesStore = defineStore('draftMessages', {
  state: () => ({
    records: LocalStorage.get(LOCAL_STORAGE_KEYS.DRAFT_MESSAGES) || {},
    replyEditorMode: REPLY_EDITOR_MODES.REPLY,
  }),

  getters: {
    get: state => key => state.records[key] || '',
    getReplyEditorMode: state => state.replyEditorMode,
  },

  actions: {
    set({ key, message }) {
      this.records = { ...this.records, [key]: message };
      persistDrafts(this.records);
    },

    delete({ key }) {
      const { [key]: _removed, ...rest } = this.records;
      this.records = rest;
      persistDrafts(this.records);
    },

    setReplyEditorMode({ mode }) {
      this.replyEditorMode = mode;
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useDraftMessagesStore, import.meta.hot)
  );
}
