<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  conversation: {
    type: Object,
    required: true,
  },
  stageColor: {
    type: String,
    default: '#94a3b8',
  },
});

const emit = defineEmits(['move', 'schedule-message', 'remove']);

const router = useRouter();
const { t } = useI18n();

const getContactById = useMapGetter('contacts/getContactById');

const contactId = computed(() => {
  return (
    props.conversation?.contactId ||
    props.conversation?.contact_id ||
    props.conversation?.contact?.id ||
    props.conversation?.meta?.sender?.id ||
    props.conversation?.sender?.id ||
    null
  );
});

const contactFromConversation = computed(() => {
  return (
    props.conversation?.contact ||
    props.conversation?.meta?.sender ||
    props.conversation?.sender ||
    null
  );
});

const contactFromStore = computed(() => {
  if (!contactId.value) return null;
  return getContactById(contactId.value);
});

const contact = computed(
  () => contactFromConversation.value || contactFromStore.value || null
);

const contactName = computed(
  () => contact.value?.name || t('KANBAN.ITEMS.UNNAMED_CONTACT')
);
const contactThumbnail = computed(() => {
  return (
    contact.value?.thumbnail ||
    contact.value?.avatar_url ||
    contact.value?.avatar ||
    contact.value?.profile_image_url ||
    ''
  );
});
const contactPhone = computed(
  () => contact.value?.phoneNumber || contact.value?.phone_number || ''
);

const lastMessage = computed(() => {
  const message =
    props.conversation?.lastMessage ||
    props.conversation?.last_message ||
    props.conversation?.lastNonActivityMessage ||
    props.conversation?.last_non_activity_message;
  return message?.content || message?.processed_message_content || '';
});

const statusColor = computed(() => {
  const status = props.conversation?.status || 'open';
  const statusMap = {
    open: 'bg-green-600',
    pending: 'bg-yellow-500',
    resolved: 'bg-gray-500',
    snoozed: 'bg-blue-500',
  };
  return statusMap[status] || 'bg-gray-500';
});

const statusIcon = computed(() => {
  const status = props.conversation?.status || 'open';
  const iconMap = {
    open: 'i-lucide-circle',
    pending: 'i-lucide-clock',
    resolved: 'i-lucide-check-circle',
    snoozed: 'i-lucide-moon',
  };
  return iconMap[status] || 'i-lucide-circle';
});

const statusTitle = computed(() => {
  const status = props.conversation?.status || 'open';
  const statusMap = {
    open: t('KANBAN.STATUS.OPEN') || 'Aberto',
    pending: t('KANBAN.STATUS.PENDING') || 'Pendente',
    resolved: t('KANBAN.STATUS.RESOLVED') || 'Resolvido',
    snoozed: t('KANBAN.STATUS.SNOOZED') || 'Adiado',
  };
  return statusMap[status] || t('KANBAN.STATUS.OPEN') || 'Aberto';
});

const openConversation = () => {
  const conversationId =
    props.conversation?.displayId ||
    props.conversation?.display_id ||
    props.conversation?.id ||
    props.conversationId;
  if (conversationId) {
    router.push({
      name: 'inbox_conversation',
      params: { conversation_id: conversationId },
    });
  }
};

let isDragging = false;
let mouseDownTime = 0;
let mouseDownX = 0;
let mouseDownY = 0;

const handleMouseDown = event => {
  isDragging = false;
  mouseDownTime = Date.now();
  mouseDownX = event.clientX;
  mouseDownY = event.clientY;

  // Permitir que o drag and drop funcione
  const handleMouseMove = () => {
    isDragging = true;
  };

  const handleMouseUp = () => {
    document.removeEventListener('mousemove', handleMouseMove);
    document.removeEventListener('mouseup', handleMouseUp);
  };

  document.addEventListener('mousemove', handleMouseMove);
  document.addEventListener('mouseup', handleMouseUp);
};

const handleCardClick = event => {
  // Se foi um drag, não abrir a conversa
  if (isDragging) {
    isDragging = false;
    return;
  }

  // Verificar se foi um clique simples (não um drag)
  const timeDiff = Date.now() - mouseDownTime;
  const xDiff = Math.abs(event.clientX - mouseDownX);
  const yDiff = Math.abs(event.clientY - mouseDownY);

  if (timeDiff < 200 && xDiff < 5 && yDiff < 5) {
    openConversation();
  }
};
</script>

<template>
  <div
    class="kanban-card bg-n-solid-3 rounded-lg p-4 cursor-pointer hover:bg-n-solid-4 border border-n-weak shadow-sm hover:shadow-lg group w-full min-w-0 transition-all duration-200 ease-out hover:-translate-y-1 flex flex-col gap-3 relative flex-shrink-0"
    :style="{ borderLeftWidth: '3px', borderLeftColor: stageColor }"
    @click="handleCardClick"
    @mousedown="handleMouseDown"
  >
    <!-- Header -->
    <div class="flex items-start justify-between gap-3">
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2.5 mb-2">
          <Avatar
            :name="contactName"
            :src="contactThumbnail"
            :size="24"
            rounded-full
            class="flex-shrink-0 ring-2 ring-n-weak"
          />
          <div class="flex-1 min-w-0">
            <h4 class="font-semibold text-sm text-n-slate-12 truncate leading-tight">
              {{ contactName }}
            </h4>
          </div>
        </div>
        <div class="pl-0.5">
          <p
            v-if="lastMessage"
            class="text-xs text-n-slate-11 line-clamp-3 leading-relaxed break-words"
          >
            {{ lastMessage }}
          </p>
          <p v-else class="text-xs text-n-slate-9 italic">
            {{ t('KANBAN.ITEMS.NO_MESSAGE') }}
          </p>
        </div>
      </div>
      <div class="flex items-start gap-1.5 flex-shrink-0">
        <div 
          class="flex items-center justify-center size-6 rounded-full border border-n-weak"
          :class="statusColor"
          :title="statusTitle"
        >
          <Icon
            :icon="statusIcon"
            class="size-3 text-white"
          />
        </div>
      </div>
    </div>

    <!-- Footer -->
    <div
      class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 gap-y-2 pt-3 border-t border-n-weak mt-1"
    >
      <div v-if="contactPhone" class="flex items-center gap-2 min-w-0">
        <div class="flex items-center justify-center size-5 rounded bg-n-solid-2">
          <Icon icon="i-lucide-phone" class="size-3 text-n-slate-10" />
        </div>
        <span
          class="text-xs text-n-slate-11 font-mono truncate font-medium"
          :title="contactPhone"
        >
          {{ contactPhone }}
        </span>
      </div>
      <div
        class="flex items-center gap-1 justify-self-end shrink-0 opacity-100 md:opacity-0 md:group-hover:opacity-100 transition-all duration-200"
        @click.stop
      >
        <Button
          size="xs"
          variant="ghost"
          icon="i-lucide-clock"
          :title="t('KANBAN.SCHEDULED_MESSAGES.CREATE') + ' - Agendar mensagem'"
          class="!h-7 !w-7 !p-0 hover:bg-n-blue-3 hover:text-n-blue-11 transition-all hover:scale-110"
          @click="emit('schedule-message', conversation)"
        />
        <Button
          size="xs"
          variant="ghost"
          icon="i-lucide-move"
          :title="t('KANBAN.ITEMS.MOVE') + ' - Mover para outra etapa'"
          class="!h-7 !w-7 !p-0 hover:bg-n-teal-3 hover:text-n-teal-11 transition-all hover:scale-110"
          @click="emit('move', item)"
        />
        <Button
          size="xs"
          variant="ghost"
          icon="i-lucide-x"
          :title="t('KANBAN.ITEMS.REMOVE') + ' - Remover do funil'"
          class="!h-7 !w-7 !p-0 hover:bg-n-ruby-3 hover:text-n-ruby-11 transition-all hover:scale-110"
          @click="emit('remove', item)"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
.kanban-card {
  min-height: 160px;
}
</style>
