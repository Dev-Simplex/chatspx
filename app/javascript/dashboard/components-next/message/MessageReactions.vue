<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  reactions: {
    type: Array,
    default: () => [],
  },
  messageId: {
    type: Number,
    required: true,
  },
  currentUserId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['add-reaction', 'remove-reaction']);

const { t } = useI18n();

// Agrupa reações por emoji
const groupedReactions = computed(() => {
  const groups = {};
  
  props.reactions.forEach(reaction => {
    if (!groups[reaction.emoji]) {
      groups[reaction.emoji] = {
        emoji: reaction.emoji,
        count: 0,
        users: [],
        hasCurrentUser: false,
      };
    }
    
    groups[reaction.emoji].count++;
    groups[reaction.emoji].users.push({
      id: reaction.user_id,
      type: reaction.user_type,
    });
    
    if (reaction.user_id === props.currentUserId && reaction.user_type === 'User') {
      groups[reaction.emoji].hasCurrentUser = true;
    }
  });
  
  return Object.values(groups);
});

const handleReactionClick = (emoji) => {
  const reactionGroup = groupedReactions.value.find(g => g.emoji === emoji);
  
  if (reactionGroup.hasCurrentUser) {
    emit('remove-reaction', { emoji, messageId: props.messageId });
  } else {
    emit('add-reaction', { emoji, messageId: props.messageId });
  }
};
</script>

<template>
  <div
    v-if="groupedReactions.length > 0"
    class="flex flex-wrap gap-1 mt-1"
  >
    <button
      v-for="group in groupedReactions"
      :key="group.emoji"
      :class="[
        'inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium transition-all duration-200',
        'hover:scale-105 active:scale-95',
        group.hasCurrentUser
          ? 'bg-woot-100 dark:bg-woot-800 border border-woot-500 text-woot-700 dark:text-woot-200'
          : 'bg-slate-100 dark:bg-slate-700 border border-slate-200 dark:border-slate-600 text-slate-700 dark:text-slate-200 hover:bg-slate-200 dark:hover:bg-slate-600'
      ]"
      :title="t('CONVERSATION.REACTION_TOOLTIP', { count: group.count })"
      @click="handleReactionClick(group.emoji)"
    >
      <span class="text-base leading-none">{{ group.emoji }}</span>
      <span class="text-xs font-semibold">{{ group.count }}</span>
    </button>
  </div>
</template>



