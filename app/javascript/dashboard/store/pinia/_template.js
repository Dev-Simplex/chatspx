import { defineStore, acceptHMRUpdate } from 'pinia';

export const useTemplateStore = defineStore('template', {
  state: () => ({
    items: [],
    uiFlags: { isFetching: false },
  }),
  getters: {
    allItems: state => state.items,
    getItemById: state => id => state.items.find(i => i.id === id),
  },
  actions: {
    async fetchAll() {
      this.uiFlags.isFetching = true;
      try {
        // const { data } = await API.get();
        // this.items = data;
      } finally {
        this.uiFlags.isFetching = false;
      }
    },
  },
  // persist: true, // descomente para persistir em localStorage
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useTemplateStore, import.meta.hot));
}
