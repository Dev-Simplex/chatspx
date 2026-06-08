import { defineStore, acceptHMRUpdate } from 'pinia';
import CustomViewsAPI from '../../api/customViews';

const VIEW_TYPES = {
  CONVERSATION: 'conversation',
  CONTACT: 'contact',
};

const FILTER_KEYS = {
  0: VIEW_TYPES.CONVERSATION,
  1: VIEW_TYPES.CONTACT,
  [VIEW_TYPES.CONVERSATION]: VIEW_TYPES.CONVERSATION,
  [VIEW_TYPES.CONTACT]: VIEW_TYPES.CONTACT,
};

// Espelho Pinia de store/modules/customViews.js (Onda 1 P0-05).
export const useCustomViewsStore = defineStore('customViews', {
  state: () => ({
    [VIEW_TYPES.CONVERSATION]: { records: [] },
    [VIEW_TYPES.CONTACT]: { records: [] },
    uiFlags: {
      isFetching: false,
      isCreating: false,
      isDeleting: false,
    },
    activeConversationFolder: null,
  }),

  getters: {
    getUIFlags: state => state.uiFlags,
    getCustomViewsByFilterType: state => key => {
      const filterType = FILTER_KEYS[key];
      return state[filterType].records;
    },
    getConversationCustomViews: state => state[VIEW_TYPES.CONVERSATION].records,
    getContactCustomViews: state => state[VIEW_TYPES.CONTACT].records,
    getActiveConversationFolder: state => state.activeConversationFolder,
  },

  actions: {
    async get(filterType) {
      this.uiFlags.isFetching = true;
      try {
        const response =
          await CustomViewsAPI.getCustomViewsByFilterType(filterType);
        const key = FILTER_KEYS[filterType] || filterType;
        this[key].records = response.data;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create(obj) {
      this.uiFlags.isCreating = true;
      try {
        const response = await CustomViewsAPI.create(obj);
        const key = FILTER_KEYS[obj.filter_type];
        this[key].records.push(response.data);
        return response;
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        throw new Error(errorMessage);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async update(obj) {
      this.uiFlags.isCreating = true;
      try {
        const response = await CustomViewsAPI.update(obj.id, obj);
        const key = FILTER_KEYS[obj.filter_type];
        const records = this[key].records;
        const index = records.findIndex(r => r.id === response.data.id);
        if (index > -1) records.splice(index, 1, response.data);
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        throw new Error(errorMessage);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async delete({ id, filterType }) {
      this.uiFlags.isDeleting = true;
      try {
        await CustomViewsAPI.deleteCustomViews(id, filterType);
        const key = FILTER_KEYS[filterType] || filterType;
        this[key].records = this[key].records.filter(r => r.id !== id);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },

    setActiveConversationFolder(folder) {
      this.activeConversationFolder = folder;
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useCustomViewsStore, import.meta.hot));
}
