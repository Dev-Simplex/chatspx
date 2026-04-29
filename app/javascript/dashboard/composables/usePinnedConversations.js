import { computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useStore, useStoreGetters } from 'dashboard/composables/store';

const KEY_USER = 'pinned_conversation_ids';
const KEY_INBOX = 'pinned_conversation_ids';

/**
 * Per-inbox pin behavior — controlled by inbox.additional_attributes.pin_mode:
 *   - 'per_agent' (default): pins live in user_uisettings.pinned_conversation_ids
 *   - 'per_inbox': pins live in inbox.additional_attributes.pinned_conversation_ids
 *                  (visible to every agent in the inbox)
 */
export function usePinnedConversations() {
  const { uiSettings, updateUISettings } = useUISettings();
  const store = useStore();
  const getters = useStoreGetters();

  const userPinnedIds = computed(() => uiSettings.value?.[KEY_USER] || []);

  const getInbox = inboxId => {
    if (!inboxId) return null;
    const fn = getters['inboxes/getInbox'];
    return fn?.value?.(Number(inboxId)) || null;
  };

  const inboxPinMode = inbox =>
    inbox?.additional_attributes?.pin_mode || 'per_agent';

  const inboxPinnedList = inbox => {
    const list = inbox?.additional_attributes?.[KEY_INBOX];
    return Array.isArray(list) ? list.map(Number) : [];
  };

  const isPinned = (id, inboxId = null) => {
    const numId = Number(id);
    if (!numId) return false;
    const inbox = getInbox(inboxId);
    if (inboxPinMode(inbox) === 'per_inbox' && inbox) {
      return inboxPinnedList(inbox).includes(numId);
    }
    return userPinnedIds.value.includes(numId);
  };

  const pin = async (id, inboxId = null) => {
    const numId = Number(id);
    if (!numId) return;
    const inbox = getInbox(inboxId);
    if (inboxPinMode(inbox) === 'per_inbox' && inbox) {
      const current = inboxPinnedList(inbox);
      if (current.includes(numId)) return;
      await store.dispatch('inboxes/updateInbox', {
        id: inbox.id,
        formData: false,
        additional_attributes: {
          ...(inbox.additional_attributes || {}),
          [KEY_INBOX]: [...current, numId],
        },
      });
      return;
    }
    if (userPinnedIds.value.includes(numId)) return;
    updateUISettings({ [KEY_USER]: [...userPinnedIds.value, numId] });
  };

  const unpin = async (id, inboxId = null) => {
    const numId = Number(id);
    if (!numId) return;
    const inbox = getInbox(inboxId);
    if (inboxPinMode(inbox) === 'per_inbox' && inbox) {
      const current = inboxPinnedList(inbox);
      await store.dispatch('inboxes/updateInbox', {
        id: inbox.id,
        formData: false,
        additional_attributes: {
          ...(inbox.additional_attributes || {}),
          [KEY_INBOX]: current.filter(p => p !== numId),
        },
      });
      return;
    }
    updateUISettings({
      [KEY_USER]: userPinnedIds.value.filter(p => p !== numId),
    });
  };

  const togglePin = (id, inboxId = null) =>
    isPinned(id, inboxId) ? unpin(id, inboxId) : pin(id, inboxId);

  // Backward-compat: pinnedIds returns the per-user list. Components that need
  // the merged set across inboxes should compute it from the inbox store.
  const pinnedIds = userPinnedIds;

  return { pinnedIds, isPinned, pin, unpin, togglePin };
}
