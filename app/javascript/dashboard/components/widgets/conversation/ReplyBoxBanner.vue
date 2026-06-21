<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import wootConstants from 'dashboard/constants/globals';
import { useReplyAssignmentGate } from 'dashboard/composables/useReplyAssignmentGate';
import { aiAccentVars } from 'dashboard/helper/aiAccent';

import Banner from 'dashboard/components/ui/Banner.vue';
import TeamSelectionModal from './TeamSelectionModal.vue';

const props = defineProps({
  message: {
    type: String,
    default: '',
  },
  isOnPrivateNote: {
    type: Boolean,
    default: false,
  },
});

// D3: gate ON faz o banner self-assign virar o caminho do dialog D2 (CTA
// emite `openAssignDialog`). Gate OFF mantém o fluxo clássico intacto.
const emit = defineEmits(['openAssignDialog']);

const store = useStore();
const { t } = useI18n();
const { isAssignmentGateEnabled } = useReplyAssignmentGate();

const currentChat = useMapGetter('getSelectedChat');
const currentUser = useMapGetter('getCurrentUser');
const teams = useMapGetter('teams/getTeams');

const assignedAgent = computed(() => currentChat.value?.meta?.assignee);
// IA como dona: a conversa é atendida pelo espelho captain. Mostra a barra roxa
// persistente "está atendendo" + CTA "Assumir", e suprime o banner genérico feio.
const isAIAssignee = computed(() => assignedAgent.value?.type === 'agent_bot');
const aiBarStyle = computed(() =>
  isAIAssignee.value && assignedAgent.value?.id
    ? aiAccentVars(assignedAgent.value.id)
    : {}
);
const showTransferTeamModal = ref(false);
const pendingTransferAgent = ref(null);
const isPendingBotHandoff = ref(false);

const isUserTyping = computed(
  () => props.message !== '' && !props.isOnPrivateNote
);
const isUnassigned = computed(() => !assignedAgent.value);
const isAssignedToOtherAgent = computed(
  () => assignedAgent.value?.id !== currentUser.value?.id
);

const showSelfAssignBanner = computed(() => {
  // IA tem barra dedicada (acima) — não duplica com o banner genérico.
  return (
    !isAIAssignee.value &&
    isUserTyping.value &&
    (isUnassigned.value || isAssignedToOtherAgent.value)
  );
});

// D3: copy/CTA do banner self-assign muda com o gate ligado — texto inclui o
// dono atual (humano OU IA via `type === 'agent_bot'`) e o CTA abre o dialog D2.
const selfAssignBannerMessage = computed(() => {
  if (!isAssignmentGateEnabled.value) {
    return t('CONVERSATION.NOT_ASSIGNED_TO_YOU');
  }
  if (isUnassigned.value) {
    return t('CONVERSATION.REPLY_GATE_BANNER.UNASSIGNED');
  }
  return t('CONVERSATION.REPLY_GATE_BANNER.TAKEN', {
    name: assignedAgent.value?.name || '',
  });
});

const selfAssignBannerActionLabel = computed(() =>
  isAssignmentGateEnabled.value
    ? t('CONVERSATION.REPLY_GATE_BANNER.CTA')
    : t('CONVERSATION.ASSIGN_TO_ME')
);

const showBotHandoffBanner = computed(
  () =>
    isUserTyping.value &&
    currentChat.value?.status === wootConstants.STATUS_TYPE.PENDING
);

const botHandoffActionLabel = computed(() => {
  return assignedAgent.value?.id === currentUser.value?.id
    ? t('CONVERSATION.BOT_HANDOFF_REOPEN_ACTION')
    : t('CONVERSATION.BOT_HANDOFF_ACTION');
});

const getCurrentUserAsAssignee = () => {
  const { avatar_url, ...rest } = currentUser.value || {};
  return { ...rest, thumbnail: avatar_url };
};

const needsAssignmentToCurrentUser = computed(() => {
  return isUnassigned.value || isAssignedToOtherAgent.value;
});

const conversationHasTeam = computed(() => {
  return Boolean(currentChat.value?.meta?.team || currentChat.value?.team_id);
});

const closeTransferTeamModal = () => {
  showTransferTeamModal.value = false;
  pendingTransferAgent.value = null;
  isPendingBotHandoff.value = false;
};

const openTransferTeamModal = () => {
  pendingTransferAgent.value = getCurrentUserAsAssignee();
  showTransferTeamModal.value = true;
};

const assignPendingAgentWithTeam = async teamId => {
  if (!pendingTransferAgent.value?.id || !currentChat.value?.id) {
    closeTransferTeamModal();
    return;
  }

  try {
    await store.dispatch('assignTeam', {
      conversationId: currentChat.value.id,
      teamId,
      rethrow: true,
    });
    await store.dispatch('assignAgent', {
      conversationId: currentChat.value.id,
      agentId: pendingTransferAgent.value.id,
      rethrow: true,
    });

    if (isPendingBotHandoff.value) {
      useAlert(t('CONVERSATION.BOT_HANDOFF_SUCCESS'));
    } else {
      useAlert(t('CONVERSATION.CHANGE_AGENT'));
    }
  } catch (error) {
    if (isPendingBotHandoff.value) {
      useAlert(t('CONVERSATION.BOT_HANDOFF_ERROR'));
    } else {
      useAlert(t('CONVERSATION.CHANGE_AGENT_FAILED'));
    }
  } finally {
    closeTransferTeamModal();
  }
};

const assignCurrentUserDirect = async ({ isBotHandoff = false } = {}) => {
  const assignee = getCurrentUserAsAssignee();
  if (!assignee?.id || !currentChat.value?.id) {
    return false;
  }

  try {
    await store.dispatch('assignAgent', {
      conversationId: currentChat.value.id,
      agentId: assignee.id,
      rethrow: true,
    });
    useAlert(
      isBotHandoff
        ? t('CONVERSATION.BOT_HANDOFF_SUCCESS')
        : t('CONVERSATION.CHANGE_AGENT')
    );
    return true;
  } catch (error) {
    useAlert(
      isBotHandoff
        ? t('CONVERSATION.BOT_HANDOFF_ERROR')
        : t('CONVERSATION.CHANGE_AGENT_FAILED')
    );
    return false;
  }
};

const onClickSelfAssign = async () => {
  if (conversationHasTeam.value) {
    await assignCurrentUserDirect();
    return;
  }
  openTransferTeamModal();
};

const onClickSelfAssignBanner = () => {
  // Gate ON: o dialog D2 é o caminho único de assunção (cobre as 4 variantes,
  // inclusive escolher time fora do time). Gate OFF: fluxo clássico intacto.
  if (isAssignmentGateEnabled.value) {
    emit('openAssignDialog');
    return;
  }
  onClickSelfAssign();
};

const reopenConversation = async () => {
  await store.dispatch('toggleStatus', {
    conversationId: currentChat.value?.id,
    status: wootConstants.STATUS_TYPE.OPEN,
  });
};

const onClickBotHandoff = async () => {
  try {
    await reopenConversation();

    if (needsAssignmentToCurrentUser.value) {
      if (conversationHasTeam.value) {
        await assignCurrentUserDirect({ isBotHandoff: true });
        return;
      }

      isPendingBotHandoff.value = true;
      openTransferTeamModal();
      return;
    }

    useAlert(t('CONVERSATION.BOT_HANDOFF_SUCCESS'));
  } catch (error) {
    useAlert(t('CONVERSATION.BOT_HANDOFF_ERROR'));
  }
};
</script>

<template>
  <!-- Barra de IA (estilo Intercom Fin): identidade roxa persistente enquanto a
       IA é a dona, com brilho sutil que "respira" e CTA claro para assumir. -->
  <div
    v-if="isAIAssignee"
    class="ai-attending-bar relative mx-2 mb-2 flex items-center gap-3 overflow-hidden rounded-xl border border-n-violet-5 bg-gradient-to-r from-n-violet-3 to-n-violet-2 px-3 py-2 dark:border-n-violet-6"
    :style="aiBarStyle"
  >
    <span class="ai-attending-bar__glow" aria-hidden="true" />
    <span
      class="ai-attending-bar__icon relative z-10 flex size-7 flex-shrink-0 items-center justify-center rounded-full bg-[var(--ai-bg)] text-[var(--ai-text)] dark:bg-[var(--ai-dark-bg)] dark:text-[var(--ai-dark-text)]"
    >
      <span class="i-lucide-sparkles size-4" />
    </span>
    <div class="relative z-10 flex min-w-0 flex-col leading-tight">
      <span class="truncate text-sm font-medium text-n-violet-12">
        {{
          $t('CONVERSATION.AI_HANDLING_HINT', {
            name: assignedAgent?.name || '',
          })
        }}
      </span>
      <span class="truncate text-xs text-n-violet-11">
        {{ $t('CONVERSATION.AI_HANDLING_SUBHINT') }}
      </span>
    </div>
    <button
      type="button"
      class="ai-attending-bar__cta relative z-10 ml-auto flex-shrink-0 rounded-lg bg-n-violet-9 px-3 py-1.5 text-sm font-medium text-white transition-all duration-200 hover:bg-n-violet-10 hover:-translate-y-px active:translate-y-0 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-7 motion-reduce:transition-none motion-reduce:hover:translate-y-0"
      @click="onClickSelfAssign"
    >
      {{ $t('CONVERSATION.REPLY_GATE_BANNER.CTA') }}
    </button>
  </div>
  <Banner
    v-if="showSelfAssignBanner && !showBotHandoffBanner"
    action-button-variant="ghost"
    color-scheme="secondary"
    class="mx-2 mb-2 rounded-lg !py-2"
    :banner-message="selfAssignBannerMessage"
    has-action-button
    :action-button-label="selfAssignBannerActionLabel"
    @primary-action="onClickSelfAssignBanner"
  />
  <Banner
    v-if="showBotHandoffBanner"
    action-button-variant="ghost"
    color-scheme="secondary"
    class="mx-2 mb-2 rounded-lg !py-2"
    :banner-message="$t('CONVERSATION.BOT_HANDOFF_MESSAGE')"
    has-action-button
    :action-button-label="botHandoffActionLabel"
    @primary-action="onClickBotHandoff"
  />
  <TeamSelectionModal
    :show="showTransferTeamModal"
    :teams="teams"
    :title="$t('CONVERSATION.SELECT_TEAM_FOR_TRANSFER_TITLE')"
    :description="$t('CONVERSATION.SELECT_TEAM_FOR_TRANSFER_DESCRIPTION')"
    @confirm="assignPendingAgentWithTeam"
    @close="closeTransferTeamModal"
  />
</template>

<style scoped lang="scss">
/* Brilho que "varre" a barra de IA — sutil, lento, estilo Intercom/Notion. */
.ai-attending-bar__glow {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: linear-gradient(
    100deg,
    transparent 30%,
    rgb(255 255 255 / 0.22) 50%,
    transparent 70%
  );
  transform: translateX(-100%);
  animation: ai-bar-sweep 3.8s ease-in-out infinite;
}

/* O ícone sparkle "respira" com um halo pulsante na cor de IA. */
.ai-attending-bar__icon {
  animation: ai-icon-pulse 2.6s ease-in-out infinite;
}

@keyframes ai-bar-sweep {
  0% {
    transform: translateX(-100%);
  }
  60%,
  100% {
    transform: translateX(100%);
  }
}

@keyframes ai-icon-pulse {
  0%,
  100% {
    transform: scale(1);
    box-shadow: 0 0 0 0 rgb(var(--violet-9) / 0.35);
  }
  50% {
    transform: scale(1.06);
    box-shadow: 0 0 0 4px rgb(var(--violet-9) / 0);
  }
}

@media (prefers-reduced-motion: reduce) {
  .ai-attending-bar__glow,
  .ai-attending-bar__icon {
    animation: none;
  }
}
</style>
