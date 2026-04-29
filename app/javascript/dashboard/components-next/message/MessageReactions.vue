<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import MessageApi from 'dashboard/api/inbox/message';

const props = defineProps({
  messageId: { type: [Number, String], required: true },
  conversationId: { type: [Number, String], required: true },
  reactions: { type: Object, default: () => ({}) },
  currentUserId: { type: [Number, String], required: true },
  mode: {
    type: String,
    default: 'all',
    validator: v => ['all', 'picker', 'chips'].includes(v),
  },
});

const EMOJIS = ['👍', '❤️', '😂', '😮', '😢', '🙏', '👏', '🔥'];
const showPicker = ref(false);
const store = useStore();

const aggregated = computed(() => {
  const out = {};
  Object.entries(props.reactions || {}).forEach(([userId, list]) => {
    (list || []).forEach(emoji => {
      if (!out[emoji]) out[emoji] = { count: 0, users: [] };
      out[emoji].count += 1;
      out[emoji].users.push(Number(userId));
    });
  });
  return out;
});

const hasReactions = computed(() => Object.keys(aggregated.value).length > 0);

const userHasEmoji = emoji =>
  aggregated.value[emoji]?.users.includes(Number(props.currentUserId));

const toggle = async emoji => {
  showPicker.value = false;
  try {
    const { data } = await MessageApi.toggleReaction(
      props.conversationId,
      props.messageId,
      emoji
    );
    const conversationId = Number(props.conversationId);
    const messageId = Number(props.messageId);
    const conversation = store.getters.getConversationById(conversationId);
    const existing = (conversation?.messages || []).find(
      m => Number(m.id) === messageId
    );
    if (existing) {
      store.dispatch('updateMessage', {
        ...existing,
        additional_attributes: {
          ...(existing.additional_attributes || {}),
          reactions: data.reactions,
        },
      });
    }
  } catch {
    // websocket will reconcile
  }
};

const isPickerMode = computed(
  () => props.mode === 'picker' || props.mode === 'all'
);
const isChipsMode = computed(
  () => (props.mode === 'chips' || props.mode === 'all') && hasReactions.value
);
const shouldRender = computed(() => isPickerMode.value || isChipsMode.value);
const rootClass = computed(() => {
  if (props.mode === 'chips') return 'flex flex-wrap gap-1 mt-2';
  return 'relative inline-block';
});
</script>

<template>
  <!-- eslint-disable-next-line vue/no-root-v-if -->
  <div v-if="shouldRender" :class="rootClass">
    <template v-if="isPickerMode">
      <button
        type="button"
        class="reaction-trigger w-7 h-7 rounded-full bg-n-solid-1/80 backdrop-blur-sm border border-n-weak text-xs flex items-center justify-center hover:bg-n-alpha-3 transition-colors shadow-sm"
        :class="{ 'bg-n-alpha-3': showPicker }"
        :title="$t('CONVERSATION.REACTIONS.PICKER_TOOLTIP')"
        @click.stop="showPicker = !showPicker"
      >
        <span class="text-sm leading-none">+</span>
      </button>

      <div
        v-if="showPicker"
        class="absolute top-0 right-0 -translate-y-full mt-1 z-20 bg-n-solid-2 rounded-full border border-n-weak shadow-lg px-2 py-1 flex gap-1"
        @click.stop
      >
        <button
          v-for="emoji in EMOJIS"
          :key="emoji"
          type="button"
          class="text-lg w-7 h-7 hover:scale-125 transition-transform leading-none"
          @click="toggle(emoji)"
        >
          {{ emoji }}
        </button>
      </div>
    </template>

    <button
      v-for="(info, emoji) in isChipsMode ? aggregated : {}"
      :key="emoji"
      type="button"
      class="reaction-chip flex items-center gap-1 px-2 py-0.5 rounded-full border text-xs leading-none transition-colors"
      :class="
        userHasEmoji(emoji)
          ? 'bg-n-solid-blue border-n-blue-9 text-n-slate-12'
          : 'bg-n-solid-2 border-n-weak text-n-slate-12 hover:bg-n-alpha-3'
      "
      @click.stop="toggle(emoji)"
    >
      <span>{{ emoji }}</span>
      <span class="text-[11px]">{{ info.count }}</span>
    </button>
  </div>
</template>
