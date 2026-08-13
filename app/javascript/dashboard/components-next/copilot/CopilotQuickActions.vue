<script setup>
const emit = defineEmits(['send']);

const actions = [
  {
    key: 'summarize',
    label: 'COPILOT.QUICK_ACTIONS.SUMMARIZE',
    icon: 'file-text',
  },
  {
    key: 'suggest',
    label: 'COPILOT.QUICK_ACTIONS.SUGGEST_REPLY',
    icon: 'message-circle',
  },
  {
    key: 'who_should',
    label: 'COPILOT.QUICK_ACTIONS.WHO_SHOULD',
    icon: 'user-check',
  },
  {
    key: 'contact_history',
    label: 'COPILOT.QUICK_ACTIONS.CONTACT_HISTORY',
    icon: 'clock',
  },
];

const ACTION_MESSAGES = {
  summarize: 'Summarize this conversation with key points and action items',
  suggest: 'Draft a reply to the customer based on the conversation context',
  who_should: 'Who is the best agent or team to handle this conversation?',
  contact_history: 'Show the full history and context for this contact',
};

function handleAction(key) {
  emit('send', ACTION_MESSAGES[key]);
}
</script>

<template>
  <div class="flex flex-wrap gap-1.5 px-3 py-2">
    <button
      v-for="action in actions"
      :key="action.key"
      class="flex items-center gap-1 rounded-full border border-n-slate-5 bg-n-solid-1 px-2.5 py-1 text-xs text-n-slate-11 transition-colors hover:border-n-teal-6 hover:bg-n-teal-2 hover:text-n-teal-11"
      @click="handleAction(action.key)"
    >
      {{ $t(action.label) }}
    </button>
  </div>
</template>
