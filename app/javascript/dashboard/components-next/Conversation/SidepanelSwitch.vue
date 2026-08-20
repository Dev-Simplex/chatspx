<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import ScheduledMessageForm from 'dashboard/components-next/Kanban/ScheduledMessageForm.vue';
import ScheduleMessageDialog from 'dashboard/components/widgets/conversation/ScheduleMessageDialog.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { computed, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useEmitter } from 'dashboard/composables/emitter';

const { updateUISettings } = useUISettings();

const currentChat = useMapGetter('getSelectedChat');

const { uiSettings } = useUISettings();

const isContactSidebarOpen = computed(
  () => uiSettings.value.is_contact_sidebar_open
);
const showScheduledMessageForm = ref(false);
const showScheduleDialog = ref(false);

const hasActiveConversation = computed(() => Boolean(currentChat.value?.id));

const conversationForSchedule = computed(() => {
  if (!hasActiveConversation.value) return null;

  return {
    id: currentChat.value.id,
    inboxId: currentChat.value.inbox_id,
    inbox_id: currentChat.value.inbox_id,
    contact: currentChat.value?.meta?.sender || null,
    meta: currentChat.value?.meta || {},
  };
});

const toggleConversationSidebarToggle = () => {
  updateUISettings({
    is_contact_sidebar_open: !isContactSidebarOpen.value,
    is_copilot_panel_open: false,
  });
};

const handleConversationSidebarToggle = () => {
  updateUISettings({
    is_contact_sidebar_open: !isContactSidebarOpen.value,
    is_copilot_panel_open: false,
  });
};

const closeScheduledMessageForm = () => {
  showScheduledMessageForm.value = false;
};

useEmitter('open-schedule-message-form', () => {
  if (!hasActiveConversation.value) return;
  showScheduledMessageForm.value = true;
});

const keyboardEvents = {
  'Alt+KeyO': {
    action: toggleConversationSidebarToggle,
  },
};
useKeyboardEvents(keyboardEvents);
</script>

<template>
  <ButtonGroup
    class="flex flex-col justify-center items-center absolute top-36 xl:top-24 ltr:right-2 rtl:left-2 bg-n-solid-2/90 backdrop-blur-lg border border-n-weak/50 rounded-full gap-1.5 p-1.5 shadow-sm transition-shadow duration-200 hover:shadow !z-20"
  >
    <Button
      v-tooltip.top="$t('CONVERSATION.SIDEBAR.CONTACT')"
      data-testid="conversation-sidebar-contact-toggle"
      ghost
      slate
      sm
      class="!rounded-full transition-all duration-[250ms] ease-out active:!scale-95 active:!brightness-105 active:duration-75"
      :class="{
        'bg-n-alpha-2 active:shadow-sm': isContactSidebarOpen,
      }"
      icon="i-lucide-user"
      @click="handleConversationSidebarToggle"
    />
    <Button
      v-if="hasActiveConversation"
      v-tooltip.top="$t('CONVERSATION.SCHEDULE_MESSAGE.TOOLTIP')"
      data-testid="conversation-schedule-message-toggle"
      ghost
      slate
      sm
      class="!rounded-full transition-all duration-[250ms] ease-out active:!scale-95 active:!brightness-105 active:duration-75"
      :class="{ 'bg-n-alpha-2 active:shadow-sm': showScheduleDialog }"
      icon="i-lucide-calendar-clock"
      @click="showScheduleDialog = true"
    />
  </ButtonGroup>
  <!-- Diálogo próprio da conversa: ao contrário do ScheduledMessageForm do Kanban
       (que só lista caixas WAHA), este oferece todas as caixas e exige template
       quando a escolhida é WhatsApp Oficial. -->
  <ScheduleMessageDialog
    v-if="showScheduleDialog && hasActiveConversation"
    :conversation-id="currentChat.id"
    :inbox-id="currentChat.inbox_id"
    :contact-id="currentChat?.meta?.sender?.id"
    @close="showScheduleDialog = false"
  />
  <ScheduledMessageForm
    :show="showScheduledMessageForm"
    :conversation="conversationForSchedule"
    require-conversation
    @close="closeScheduledMessageForm"
    @saved="closeScheduledMessageForm"
  />
</template>
