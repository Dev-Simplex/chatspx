<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { fromUnixTime, format, isToday, isYesterday } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import Avatar from 'next/avatar/Avatar.vue';

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

  // Converter timestamp Unix (segundos) ou string ISO para Date
  let date;
  if (typeof time === 'number') {
    // Se for número, pode ser timestamp Unix (segundos) ou milissegundos
    // Timestamps Unix geralmente são menores que 1e12 (ano 2001 em milissegundos)
    if (time < 1e12) {
      // Timestamp Unix em segundos - converter para milissegundos
      date = fromUnixTime(time);
    } else {
      // Já está em milissegundos
      date = new Date(time);
    }
  } else if (typeof time === 'string') {
    // Se for string, tentar parsear como ISO ou timestamp
    const parsed = Date.parse(time);
    if (!Number.isNaN(parsed)) {
      date = new Date(parsed);
    } else {
      // Tentar como timestamp Unix
      const numTime = Number(time);
      if (!Number.isNaN(numTime)) {
        date = fromUnixTime(numTime);
      } else {
        return '';
      }
    }
  } else {
    return '';
  }

  // Verificar se a data é válida
  if (Number.isNaN(date.getTime())) {
    return '';
  }

  if (isToday(date)) {
    return format(date, 'HH:mm', { locale: ptBR });
  }
  if (isYesterday(date)) {
    return t('LIVE_REPORTS.IN_SERVICE.YESTERDAY');
  }
  return format(date, 'dd/MM/yyyy', { locale: ptBR });
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
    <Avatar
      :name="conversation.contactName"
      :src="conversation.contactAvatar"
      :size="40"
      rounded-full
    >
      <template #badge>
        <div
          class="absolute z-20 flex items-center justify-center rounded-full bg-n-brand border border-white dark:border-n-solid-2 flex-shrink-0 size-3.5 top-[26px] left-[26px]"
        >
          <span class="i-lucide-message-circle size-2.5 text-white" />
        </div>
      </template>
    </Avatar>
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
          class="flex items-center justify-center min-w-[1.25rem] h-5 px-1.5 rounded-full bg-n-brand text-white text-xs font-medium flex-shrink-0"
        >
          {{ unreadCount > 99 ? '99+' : unreadCount }}
        </span>
        <span
          v-else-if="conversation.lastMessageStatus === 'read'"
          class="flex-shrink-0 opacity-70"
        >
          <span class="i-lucide-check-check size-4 text-n-brand" />
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
