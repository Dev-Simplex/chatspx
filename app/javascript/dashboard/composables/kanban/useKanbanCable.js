// Composable que subscreve o KanbanChannel (P1-13).
// Cria um consumer dedicado ao kanban (canal distinto do RoomChannel global)
// e despacha mensagens para useKanbanRealtimeStore.handleMessage.
//
// Uso (em KanbanBoard.vue):
//   const { subscribe, unsubscribe } = useKanbanCable();
//   onMounted(() => subscribe(kanbanId));
//   onUnmounted(() => unsubscribe());
//
// O consumer é compartilhado em window.__kanbanCable para reuso entre montagens.

import { createConsumer } from '@rails/actioncable';
import { useAuthStore } from 'dashboard/store/pinia/useAuthStore';
import { useKanbanRealtimeStore } from 'dashboard/store/pinia/kanban/realtime';

let sharedConsumer = null;
let activeSubscription = null;

function getConsumer() {
  if (sharedConsumer) return sharedConsumer;
  sharedConsumer = createConsumer();
  return sharedConsumer;
}

export function useKanbanCable() {
  const auth = useAuthStore();
  const realtime = useKanbanRealtimeStore();

  const unsubscribe = () => {
    if (activeSubscription) {
      try {
        activeSubscription.unsubscribe();
      } catch (_) {
        // ignore
      }
      activeSubscription = null;
    }
    realtime.reset();
  };

  const subscribe = kanbanId => {
    if (!kanbanId) return;
    unsubscribe();

    const user = auth.currentUser || {};
    const accountId =
      auth.currentAccountId ||
      auth.getCurrentAccountId ||
      user.account_id ||
      (window?.$store?.getters?.getCurrentAccountId ?? null);
    if (!user.id || !accountId || !user.pubsub_token) return;

    realtime.setSubscription(kanbanId);

    activeSubscription = getConsumer().subscriptions.create(
      {
        channel: 'KanbanChannel',
        kanban_id: Number(kanbanId),
        account_id: Number(accountId),
        user_id: Number(user.id),
        pubsub_token: user.pubsub_token,
      },
      {
        connected: () => realtime.setConnected(true),
        disconnected: () => realtime.setConnected(false),
        received: msg => realtime.handleMessage(msg),
      }
    );
  };

  return { subscribe, unsubscribe };
}
