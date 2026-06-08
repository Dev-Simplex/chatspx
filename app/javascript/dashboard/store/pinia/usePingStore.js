import { defineStore, acceptHMRUpdate } from 'pinia';

export const usePingStore = defineStore('ping', {
  state: () => ({ value: 'pong' }),
  actions: {
    pong() {
      return this.value;
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(usePingStore, import.meta.hot));
}
