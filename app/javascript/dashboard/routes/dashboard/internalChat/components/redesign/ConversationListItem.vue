<script setup>
import { computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
  active: { type: Boolean, default: false },
});

defineEmits(['select']);

const preview = computed(() => {
  const lm = props.conversation.lastMessage || {};
  return lm.fromMe ? `Você: ${lm.preview}` : lm.preview;
});

// Only show the green presence dot for online people (groups/offline: none).
const status = computed(() =>
  props.conversation.presence === 'online' ? 'online' : null
);
</script>

<template>
  <button
    type="button"
    class="flex items-center w-full gap-3 px-3 py-2.5 text-left transition-colors rounded-xl"
    :class="active ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
    @click="$emit('select', conversation.id)"
  >
    <Avatar
      :name="conversation.name"
      :src="conversation.avatarSrc || ''"
      :icon-name="conversation.iconName"
      :size="44"
      :status="status"
      rounded-full
    />
    <span class="flex-1 min-w-0">
      <span class="flex items-baseline justify-between gap-2">
        <span
          class="text-sm truncate text-n-slate-12"
          :class="conversation.unreadCount ? 'font-semibold' : 'font-medium'"
        >
          {{ conversation.name }}
        </span>
        <span
          class="text-xs flex-shrink-0"
          :class="
            conversation.unreadCount
              ? 'text-n-brand font-medium'
              : 'text-n-slate-10'
          "
        >
          {{ conversation.time }}
        </span>
      </span>
      <span class="flex items-center justify-between gap-2 mt-0.5">
        <span
          class="block text-xs truncate"
          :class="
            conversation.unreadCount ? 'text-n-slate-12' : 'text-n-slate-10'
          "
        >
          {{ preview }}
        </span>
        <span
          v-if="conversation.unreadCount"
          class="inline-flex items-center justify-center min-w-[20px] h-5 px-1.5 text-[11px] font-semibold text-white rounded-full bg-n-brand flex-shrink-0"
        >
          {{ conversation.unreadCount }}
        </span>
      </span>
    </span>
  </button>
</template>
