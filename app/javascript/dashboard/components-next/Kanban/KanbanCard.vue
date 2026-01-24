<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
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
    open: 'bg-green-500',
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
    class="bg-n-solid-3 rounded-lg p-4 cursor-pointer hover:bg-n-solid-4 border border-n-weak shadow-sm hover:shadow-md group w-full min-w-0 transition duration-200 ease-out hover:-translate-y-0.5 flex flex-col gap-3"
    @click="handleCardClick"
    @mousedown="handleMouseDown"
  >
    <!-- Header -->
    <div class="flex items-start justify-between">
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 mb-1">
          <Avatar
            :name="contactName"
            :src="contactThumbnail"
            :size="20"
            rounded-full
          />
          <h4 class="font-semibold text-sm text-n-slate-12 truncate">
            {{ contactName }}
          </h4>
        </div>
        <p
          v-if="lastMessage"
          class="text-xs text-n-slate-11 mt-1 line-clamp-2 leading-relaxed"
        >
          {{ lastMessage }}
        </p>
        <p v-else class="text-xs text-n-slate-9 italic mt-1">
          {{ t('KANBAN.ITEMS.NO_MESSAGE') }}
        </p>
      </div>
      <div class="flex items-center gap-1.5 flex-shrink-0 ml-2">
        <Icon
          :icon="statusIcon"
          class="size-3"
          :class="statusColor"
          :title="statusTitle"
        />
      </div>
    </div>

    <!-- Footer -->
    <div
      class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-2 gap-y-2 pt-3 border-t border-n-weak"
    >
      <div v-if="contactPhone" class="flex items-center gap-2 min-w-0">
        <Icon icon="i-lucide-phone" class="size-3 text-n-slate-9" />
        <span
          class="text-xs text-n-slate-10 font-mono truncate"
          :title="contactPhone"
        >
          {{ contactPhone }}
        </span>
      </div>
      <div
        class="flex items-center gap-1 justify-self-end shrink-0 opacity-100 md:opacity-0 md:group-hover:opacity-100 transition-opacity"
        @click.stop
      >
        <Button
          size="xs"
          variant="ghost"
          icon="i-lucide-clock"
          :title="t('KANBAN.SCHEDULED_MESSAGES.CREATE')"
          class="!h-7 !w-7 !p-0"
          @click="emit('schedule-message', conversation)"
        />
        <Button
          size="xs"
          variant="ghost"
          icon="i-lucide-move"
          :title="t('KANBAN.ITEMS.MOVE')"
          class="!h-7 !w-7 !p-0"
          @click="emit('move', item)"
        />
        <Button
          size="xs"
          variant="ghost"
          icon="i-lucide-x"
          :title="t('KANBAN.ITEMS.REMOVE')"
          class="!h-7 !w-7 !p-0"
          @click="emit('remove', item)"
        />
      </div>
    </div>
  </div>
</template>
