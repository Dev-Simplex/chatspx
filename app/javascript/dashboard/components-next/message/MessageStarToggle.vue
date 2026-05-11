<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import MessageApi from 'dashboard/api/inbox/message';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  messageId: { type: [Number, String], required: true },
  conversationId: { type: [Number, String], required: true },
  starred: { type: Boolean, default: false },
});

const store = useStore();
const localStarred = ref(props.starred);
const isPending = ref(false);

const isOn = computed(() => localStarred.value || props.starred);

const toggle = async () => {
  if (isPending.value) return;
  isPending.value = true;
  const previous = localStarred.value;
  localStarred.value = !previous;
  try {
    const { data } = await MessageApi.toggleStar(
      props.conversationId,
      props.messageId
    );
    localStarred.value = !!data.starred;
    const conversationId = Number(props.conversationId);
    const messageId = Number(props.messageId);
    const conversation = store.getters.getConversationById(conversationId);
    const existing = (conversation?.messages || []).find(
      m => Number(m.id) === messageId
    );
    if (existing) {
      store.dispatch('updateMessage', {
        ...existing,
        starred: !!data.starred,
      });
    }
  } catch {
    localStarred.value = previous;
  } finally {
    isPending.value = false;
  }
};
</script>

<template>
  <button
    type="button"
    class="w-7 h-7 rounded-full bg-n-solid-1/80 backdrop-blur-sm border border-n-weak flex items-center justify-center hover:bg-n-alpha-3 transition-colors shadow-sm"
    :class="isOn ? 'text-n-amber-11' : 'text-n-slate-11'"
    :title="
      $t(
        isOn
          ? 'CONVERSATION.CONTEXT_MENU.UNSTAR'
          : 'CONVERSATION.CONTEXT_MENU.STAR'
      )
    "
    @click.stop="toggle"
  >
    <Icon
      :icon="isOn ? 'i-lucide-star' : 'i-lucide-star'"
      class="w-3.5 h-3.5"
      :class="isOn ? 'fill-current' : ''"
    />
  </button>
</template>
