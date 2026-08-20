<script setup>
import { computed, onUnmounted, ref } from 'vue';
import { useToggle } from '@vueuse/core';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import EmailTranscriptModal from './EmailTranscriptModal.vue';
import EvaluateEpisodeModal from './EvaluateEpisodeModal.vue';
import ShareToInternalChat from './ShareToInternalChat.vue';
import ResolveAction from '../../buttons/ResolveAction.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import {
  CMD_MUTE_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';
import { BUS_EVENTS } from 'shared/constants/busEvents';

// No props needed as we're getting currentChat from the store directly
const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();

const [showEmailActionsModal, toggleEmailModal] = useToggle(false);
const [showActionsDropdown, toggleDropdown] = useToggle(false);
const [showShareToInternalChat, toggleShareToInternalChat] = useToggle(false);
const [showEvaluateModal, toggleEvaluateModal] = useToggle(false);
// Âncora opcional do modal de avaliação (setada pelo menu ⋮ de uma mensagem):
// pré-seleciona o episódio da mensagem e cita o trecho na observação.
const evalAnchor = ref(null);

const openEvalModal = payload => {
  evalAnchor.value = payload || null;
  toggleEvaluateModal(true);
};

const closeEvalModal = () => {
  evalAnchor.value = null;
  toggleEvaluateModal(false);
};

const currentChat = computed(() => store.getters.getSelectedChat);
const currentUser = computed(() => store.getters.getCurrentUser);

// "Devolver para a IA" só quando a conversa é minha (mesmo par do "Atribuir a
// mim" da sidebar) — não devolve conversa de outro agente nem da própria IA.
const isAssignedToMe = computed(() => {
  const assignee = currentChat.value?.meta?.assignee;
  return Boolean(
    assignee &&
      assignee.type !== 'agent_bot' &&
      assignee.id === currentUser.value?.id
  );
});

// "Devolver para a IA" no header: além de ser minha, precisa haver IA atribuível
// nesta inbox (logo, triagem possível). O backend valida se há triagem de fato.
const canRetriage = computed(
  () =>
    isAssignedToMe.value &&
    (store.getters['captainAssistants/getRecords'] || []).some(
      assistant =>
        assistant.agent_bot_id &&
        (assistant.inbox_ids || []).includes(currentChat.value?.inbox_id)
    )
);
const hasInternalChat = computed(() => {
  const accountId = store.getters.getCurrentAccountId;
  return store.getters['accounts/isFeatureEnabledonAccount'](
    accountId,
    FEATURE_FLAGS.INTERNAL_CHAT
  );
});

const actionMenuItems = computed(() => {
  const items = [];

  if (canRetriage.value) {
    items.push({
      icon: 'i-lucide-sparkles',
      label: t('CONVERSATION_SIDEBAR.RETRIAGE'),
      action: 'retriage',
      value: 'retriage',
    });
  }

  if (hasInternalChat.value) {
    items.push({
      icon: 'i-lucide-messages-square',
      label: t('INTERNAL_CHAT.SHARE.MENU_ITEM'),
      action: 'share_to_internal_chat',
      value: 'share_to_internal_chat',
    });
  }

  if (!currentChat.value.muted) {
    items.push({
      // PR D4 — Backend "mute" action blocks the contact (contact.blocked=true).
      // Icon now reflects "block" semantics instead of audio mute.
      icon: 'i-lucide-ban',
      label: t('CONTACT_PANEL.MUTE_CONTACT'),
      action: 'mute',
      value: 'mute',
    });
  } else {
    items.push({
      icon: 'i-lucide-check-circle',
      label: t('CONTACT_PANEL.UNMUTE_CONTACT'),
      action: 'unmute',
      value: 'unmute',
    });
  }

  items.push({
    icon: 'i-lucide-share',
    label: t('CONTACT_PANEL.SEND_TRANSCRIPT'),
    action: 'send_transcript',
    value: 'send_transcript',
  });

  // F4.2 (Eval humano): avaliação da gestão por episódio, só pra admins.
  if (isAdmin.value) {
    items.push({
      icon: 'i-lucide-clipboard-check',
      label: t('EVALUATE_EPISODE.MENU_ITEM'),
      action: 'evaluate_episode',
      value: 'evaluate_episode',
    });
  }

  return items;
});

const onRetriage = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CONVERSATION_SIDEBAR.RETRIAGE_CONFIRM'))) {
    return;
  }
  try {
    await store.dispatch('retriage', {
      conversationId: currentChat.value.id,
      rethrow: true,
    });
    useAlert(t('CONVERSATION_SIDEBAR.RETRIAGE_SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CONVERSATION_SIDEBAR.RETRIAGE_ERROR')
    );
  }
};

const handleActionClick = ({ action }) => {
  toggleDropdown(false);

  if (action === 'mute') {
    store.dispatch('muteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
  } else if (action === 'unmute') {
    store.dispatch('unmuteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
  } else if (action === 'send_transcript') {
    toggleEmailModal();
  } else if (action === 'retriage') {
    onRetriage();
  } else if (action === 'share_to_internal_chat') {
    toggleShareToInternalChat(true);
  } else if (action === 'evaluate_episode') {
    openEvalModal(null);
  }
};

// These functions are needed for the event listeners
const mute = () => {
  store.dispatch('muteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
};

const unmute = () => {
  store.dispatch('unmuteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
};

emitter.on(CMD_MUTE_CONVERSATION, mute);
emitter.on(CMD_UNMUTE_CONVERSATION, unmute);
emitter.on(CMD_SEND_TRANSCRIPT, toggleEmailModal);
emitter.on(BUS_EVENTS.OPEN_EVAL_MODAL, openEvalModal);

onUnmounted(() => {
  emitter.off(CMD_MUTE_CONVERSATION, mute);
  emitter.off(CMD_UNMUTE_CONVERSATION, unmute);
  emitter.off(CMD_SEND_TRANSCRIPT, toggleEmailModal);
  emitter.off(BUS_EVENTS.OPEN_EVAL_MODAL, openEvalModal);
});
</script>

<template>
  <div class="relative flex items-center gap-1 actions--container">
    <ResolveAction
      :conversation-id="currentChat.id"
      :status="currentChat.status"
    />
    <div
      v-on-clickaway="() => toggleDropdown(false)"
      class="relative flex items-center"
    >
      <ButtonV4
        v-tooltip="$t('CONVERSATION.HEADER.MORE_ACTIONS')"
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-more-vertical"
        class="size-8 rounded-lg hover:bg-n-slate-3/50 text-n-slate-10 hover:text-n-slate-12"
        @click="toggleDropdown()"
      />
      <DropdownMenu
        v-if="showActionsDropdown"
        :menu-items="actionMenuItems"
        class="mt-1 ltr:right-0 rtl:left-0 top-full"
        @action="handleActionClick"
      />
    </div>
    <EmailTranscriptModal
      v-if="showEmailActionsModal"
      :show="showEmailActionsModal"
      :current-chat="currentChat"
      @cancel="toggleEmailModal"
    />
    <ShareToInternalChat
      v-if="showShareToInternalChat"
      :show="showShareToInternalChat"
      :conversation="currentChat"
      @close="toggleShareToInternalChat(false)"
    />
    <EvaluateEpisodeModal
      v-if="showEvaluateModal"
      :show="showEvaluateModal"
      :current-chat="currentChat"
      :anchor="evalAnchor"
      @cancel="closeEvalModal"
    />
  </div>
</template>
