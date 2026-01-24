<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();

const unreadCount = computed(() => props.conversation.unreadCount || 0);
const hasUnread = computed(() => unreadCount.value > 0);

const formatTime = time => {
  if (!time) return '';
  const date = new Date(time);
  const now = new Date();
  const diffInHours = (now - date) / (1000 * 60 * 60);

  if (diffInHours < 24) {
    return date.toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
    });
  } else if (diffInHours < 48) {
    return 'Ontem';
  } else {
    return date.toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
    });
  }
};

const handleConversationClick = () => {
  if (accountId.value && props.conversation.id) {
    // Navegar para a conversa usando a rota do Chatwoot
    router.push({
      name: 'inbox_conversation',
      params: {
        accountId: accountId.value,
        conversation_id: props.conversation.id,
      },
    });
  }
};
</script>

<template>
  <div
    class="flex items-start gap-3 p-3 rounded-lg hover:bg-n-alpha-2 transition-all duration-200 cursor-pointer group active:bg-n-alpha-3"
    @click="handleConversationClick"
  >
    <Thumbnail
      :username="conversation.contactName"
      :src="conversation.contactAvatar"
      size="40px"
      badge="whatsapp"
    />
    <div class="flex-1 min-w-0">
      <div class="flex items-center justify-between gap-2 mb-1">
        <h6
          class="text-sm font-medium text-n-slate-12 truncate m-0 group-hover:text-n-brand transition-colors"
          :title="conversation.contactName"
        >
          {{ conversation.contactName }}
        </h6>
        <span class="text-xs text-n-slate-11 flex-shrink-0">
          {{ formatTime(conversation.lastMessageTime) }}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <p
          class="text-sm text-n-slate-11 m-0 truncate flex-1"
          :title="conversation.lastMessage"
        >
          {{ conversation.lastMessage }}
        </p>
        <span
          v-if="hasUnread"
          class="flex items-center justify-center min-w-[1.25rem] h-5 px-1.5 rounded-full bg-n-ruby-9 text-white text-xs font-medium flex-shrink-0 animate-pulse"
        >
          {{ unreadCount > 99 ? '99+' : unreadCount }}
        </span>
        <span
          v-else-if="conversation.lastMessageStatus === 'read'"
          class="flex-shrink-0 opacity-70"
        >
          <span class="i-lucide-check-check size-4 text-n-teal-10" />
        </span>
        <span
          v-else-if="conversation.lastMessageStatus === 'sent'"
          class="flex-shrink-0 opacity-70"
        >
          <span class="i-lucide-check size-4 text-n-slate-11" />
        </span>
      </div>
    </div>
  </div>
</template>

<style scoped>
@keyframes slideIn {
  from {
    opacity: 0;
    transform: translateY(-4px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.group {
  animation: slideIn 0.3s ease-out;
}
</style>
