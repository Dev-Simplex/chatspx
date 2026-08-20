import { computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';

/**
 * Picks which Captain assistant backs the copilot thread.
 *
 * Same precedence the legacy `CopilotContainer` uses (user preference → the
 * inbox's assistant → the first one in the account), duplicated here instead
 * of imported because the legacy container is going away and this panel must
 * not depend on it.
 *
 * The copilot only READS the assistant (persona, knowledge, temperature) —
 * it never writes to it. That boundary is the whole point of the "zona
 * proibida" rule in the briefing.
 */
export function useCopilotAssistant() {
  const store = useStore();
  const { uiSettings } = useUISettings();
  const assistants = useMapGetter('captainAssistants/getRecords');
  const inboxAssistant = useMapGetter('getCopilotAssistant');

  const activeAssistant = computed(() => {
    const list = assistants.value || [];
    const preferredId = uiSettings.value?.preferred_captain_assistant_id;
    if (preferredId) {
      const preferred = list.find(a => a.id === preferredId);
      if (preferred) return preferred;
    }
    if (inboxAssistant.value) {
      const matched = list.find(a => a.id === inboxAssistant.value.id);
      if (matched) return matched;
    }
    return list[0];
  });

  const hasAssistant = computed(() => Boolean(activeAssistant.value?.id));

  function fetchAssistants() {
    if (assistants.value?.length) return Promise.resolve();
    return store.dispatch('captainAssistants/get');
  }

  return { assistants, activeAssistant, hasAssistant, fetchAssistants };
}
