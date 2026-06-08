// Pinia store de estado do KanbanChannel (P1-13).
// Mantém conexão, Lamport seq, e despacha eventos para useKanbanBoardStore.

import { defineStore, acceptHMRUpdate } from 'pinia';
import { useKanbanBoardStore } from './board';

function safeParse(str) {
  try {
    return JSON.parse(str);
  } catch (_) {
    return null;
  }
}

export const useKanbanRealtimeStore = defineStore('kanbanRealtime', {
  state: () => ({
    connected: false,
    subscribedKanbanId: null,
    lastSeq: 0,
    lastEventAt: null,
  }),

  actions: {
    setConnected(value) {
      this.connected = Boolean(value);
    },

    setSubscription(kanbanId) {
      this.subscribedKanbanId = kanbanId == null ? null : Number(kanbanId);
      this.lastSeq = 0;
    },

    handleMessage(message) {
      if (!message) return;
      const evt = typeof message === 'string' ? safeParse(message) : message;
      if (!evt || !evt.event) return;

      // Lamport tie-breaker
      const seq = Number(evt.seq || 0);
      if (seq && seq <= this.lastSeq) return; // descarta evento antigo
      if (seq) this.lastSeq = seq;
      this.lastEventAt = Date.now();

      const board = useKanbanBoardStore();
      board.applyRemoteEvent(evt);
    },

    reset() {
      this.connected = false;
      this.subscribedKanbanId = null;
      this.lastSeq = 0;
      this.lastEventAt = null;
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useKanbanRealtimeStore, import.meta.hot)
  );
}
