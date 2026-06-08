// KANBAN-P3-07: tooltip educativo first-time.
// Persistência: localStorage (`chatspx.kanban_tooltips_seen`) + opcional sync
// pro backend via UI prefs futura. Singleton reativo.
import { reactive, computed } from 'vue';

const STORAGE_KEY = 'chatspx.kanban_tooltips_seen';

const safeRead = () => {
  try {
    const raw = window.localStorage?.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
};

const safeWrite = data => {
  try {
    window.localStorage?.setItem(STORAGE_KEY, JSON.stringify(data));
  } catch {
    /* no-op */
  }
};

const state = reactive({
  seen: safeRead(),
});

export function useFirstTimeTooltip() {
  const isSeen = key => Boolean(state.seen[key]);

  const dismiss = key => {
    state.seen = { ...state.seen, [key]: Date.now() };
    safeWrite(state.seen);
  };

  const reset = () => {
    state.seen = {};
    safeWrite(state.seen);
  };

  // FIFO de tooltips por ordem em que apareceram. Mostra UM por vez.
  const tooltipsOrder = [
    {
      key: 'first_open_card',
      messageKey: 'KANBAN.TOOLTIPS.FIRST_OPEN_CARD',
      icon: 'i-lucide-mouse-pointer-click',
    },
    {
      key: 'first_drag',
      messageKey: 'KANBAN.TOOLTIPS.FIRST_DRAG',
      icon: 'i-lucide-move',
    },
    {
      key: 'first_shortcuts',
      messageKey: 'KANBAN.TOOLTIPS.FIRST_SHORTCUTS',
      icon: 'i-lucide-keyboard',
    },
  ];

  const nextTooltip = computed(
    () => tooltipsOrder.find(t => !isSeen(t.key)) || null
  );

  return {
    isSeen,
    dismiss,
    reset,
    nextTooltip,
  };
}
