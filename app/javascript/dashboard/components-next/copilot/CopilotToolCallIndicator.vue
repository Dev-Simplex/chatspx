<script setup>
defineProps({
  toolName: { type: String, default: '' },
  isLoading: { type: Boolean, default: true },
  result: { type: String, default: '' },
});

const TOOL_LABELS = {
  get_account_stats: 'Fetching account stats...',
  get_agent_workload: 'Checking agent workload...',
  get_team_info: 'Loading team info...',
  assign_conversation: 'Assigning conversation...',
  add_label: 'Adding label...',
  change_status: 'Changing status...',
  change_priority: 'Changing priority...',
  get_csat_data: 'Loading CSAT data...',
  search_messages: 'Searching messages...',
  get_inbox_info: 'Loading inbox info...',
  get_conversation_full: 'Loading conversation details...',
  search_documentation: 'Searching documentation...',
  get_conversation: 'Loading conversation...',
  search_conversation: 'Searching conversations...',
};
</script>

<template>
  <div
    class="flex items-center gap-2 rounded-md bg-n-slate-2 px-3 py-1.5 text-xs text-n-slate-12"
  >
    <span
      v-if="isLoading"
      class="inline-block h-3 w-3 animate-spin rounded-full border-2 border-n-teal-6 border-t-transparent"
    />
    <span v-else class="text-green-600">&#10003;</span>
    <span>{{ TOOL_LABELS[toolName] || `Running ${toolName}...` }}</span>
  </div>
</template>
