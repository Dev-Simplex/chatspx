import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

/**
 * Single source of truth for the `reply_assignment_gate` account setting
 * (mandatory assignment mode). Options API components should call this
 * inside `setup()`.
 * @returns {{ isAssignmentGateEnabled: import('vue').ComputedRef<boolean> }}
 */
export function useReplyAssignmentGate() {
  const { currentAccount } = useAccount();
  const isAssignmentGateEnabled = computed(() =>
    Boolean(currentAccount.value?.settings?.reply_assignment_gate)
  );
  return { isAssignmentGateEnabled };
}
