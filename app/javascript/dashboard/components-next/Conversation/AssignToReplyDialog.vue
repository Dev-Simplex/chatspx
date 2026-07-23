<script setup>
// D2 / D-L2 — Dialog "Quer atribuir a você?" do gate universal de resposta.
// Embrulha o Dialog components-next (focus trap / ESC / a11y nativos) e
// resolve 4 variantes a partir do estado da conversa:
//   (a) conversa SEM dono  -> "Atribuir a mim e enviar" (self-assign;
//       SEM exigir time quando a conversa não tem time — AD-15 / OQ-D4)
//   (b) dono humano (colega) -> "Assumir de {nome} e enviar"
//   (c) dona IA (assignee.type === 'agent_bot') -> "Assumir da {IA} e enviar"
//   (d) fora do time (admin ou agente) -> escolher um dos times DO usuário
//       (teams/getMyTeams — NUNCA todos os times da conta) + "Atribuir e enviar"
//
// Animação de entrada: spring físico via motion-v (D8) sobre o conteúdo —
// o slot só renderiza com o dialog aberto (Dialog.vue), então o mount anima.
// `MotionConfig reduced-motion="user"` global (App.vue) zera a física quando
// prefers-reduced-motion está ativo.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Motion } from 'motion-v';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { fireTakeoverConfetti } from 'dashboard/components-next/effects/useConfetti';

const emit = defineEmits(['confirm']);
const { t } = useI18n();
const store = useStore();
const { currentAccount } = useAccount();

const currentChat = useMapGetter('getSelectedChat');
const currentUser = useMapGetter('getCurrentUser');
const myTeams = useMapGetter('teams/getMyTeams');
const allTeams = useMapGetter('teams/getTeams');

const dialogRef = ref(null);
// meta do 422 (D6) — dono ATUALIZADO numa corrida (P16). Tem prioridade
// sobre o store, que pode estar atrasado um tick após o segundo agente assumir.
const overrideMeta = ref(null);
const selectedTeamId = ref(null);
const isLoading = ref(false);
const errorMessage = ref('');

const assigneeInfo = computed(() => {
  if (overrideMeta.value) {
    const ca = overrideMeta.value.current_assignee;
    return ca
      ? { id: ca.id, name: ca.name, isAI: ca.type === 'AgentBot' }
      : null;
  }
  const a = currentChat.value?.meta?.assignee;
  return a
    ? {
        id: a.id,
        name: a.available_name || a.name,
        isAI: a.type === 'agent_bot',
      }
    : null;
});

const conversationTeam = computed(() => {
  if (overrideMeta.value?.team) return overrideMeta.value.team;
  if (currentChat.value?.meta?.team) return currentChat.value.meta.team;
  if (currentChat.value?.team_id) return { id: currentChat.value.team_id };
  return null;
});

// fail-open quando o store de teams ainda não carregou (precedente
// ConversationAction.vue): sem times conhecidos, assume que sou membro
// para não bloquear a assunção indevidamente.
const isMemberOfConversationTeam = computed(() => {
  if (!conversationTeam.value) return true;
  if (!allTeams.value.length) return true;
  return myTeams.value.some(team => team.id === conversationTeam.value.id);
});

const variant = computed(() => {
  if (!isMemberOfConversationTeam.value) return 'd'; // fora do time
  if (assigneeInfo.value?.isAI) return 'c'; // dona IA
  if (assigneeInfo.value) return 'b'; // dono humano (colega)
  return 'a'; // sem dono
});

// D1 (Fase 3): com o takeover_request_gate ligado, a variante (b) — dono humano
// (colega) — deixa de ASSUMIR e passa a SOLICITAR. As outras variantes (sem
// dono / IA / fora do time) seguem intactas: nelas não há de quem "tomar".
const isTakeoverGateEnabled = computed(() =>
  Boolean(currentAccount.value?.settings?.takeover_request_gate)
);
const isRequestFlow = computed(
  () => isTakeoverGateEnabled.value && variant.value === 'b'
);

// DD-5: variante (a/b/c) em conversa SEM time + usuário com 1+ times →
// select dos MEUS times (pré-seleciona quando há 1 só). 0 times = self-assign
// puro (a conversa mantém o time atual; AD-15 / OQ-D4 não exigem time).
// Só exige escolher um time quando o usuário TEM times. Com 0 times (ex.: admin
// fora de qualquer time) a variante (d) vira self-assign puro mantendo o time
// atual da conversa — senão o botão "Atribuir e enviar" trava sem opção possível.
const needsTeamSelection = computed(
  () =>
    myTeams.value.length > 0 &&
    (variant.value === 'd' || !conversationTeam.value)
);

const canConfirm = computed(
  () => !needsTeamSelection.value || Boolean(selectedTeamId.value)
);

const title = computed(() =>
  t(`CONVERSATION.REPLY_GATE_DIALOG.TITLE.${variant.value.toUpperCase()}`, {
    name: assigneeInfo.value?.name || '',
  })
);

const description = computed(() =>
  t(`CONVERSATION.REPLY_GATE_DIALOG.DESC.${variant.value.toUpperCase()}`, {
    name: assigneeInfo.value?.name || '',
    team: conversationTeam.value?.name || '',
  })
);

const confirmLabel = computed(() => {
  if (isRequestFlow.value) {
    return t('CONVERSATION.TAKEOVER_REQUEST.CONFIRM');
  }
  return t(
    `CONVERSATION.REPLY_GATE_DIALOG.CONFIRM.${variant.value.toUpperCase()}`,
    {
      name: assigneeInfo.value?.name || '',
    }
  );
});

const dialogTitle = computed(() =>
  isRequestFlow.value ? t('CONVERSATION.TAKEOVER_REQUEST.TITLE') : title.value
);

const dialogDescription = computed(() =>
  isRequestFlow.value
    ? t('CONVERSATION.TAKEOVER_REQUEST.DESC', {
        name: assigneeInfo.value?.name || '',
        team: conversationTeam.value?.name || '',
      })
    : description.value
);

const show = (meta = null) => {
  overrideMeta.value = meta;
  errorMessage.value = '';
  selectedTeamId.value = null;
  if (needsTeamSelection.value && myTeams.value.length === 1) {
    selectedTeamId.value = myTeams.value[0].id;
  }
  // idempotente: showModal num dialog já aberto é no-op (dedupe dos N 422
  // do multi-part).
  dialogRef.value?.open();
};

const hide = () => dialogRef.value?.close();

defineExpose({ show, hide });

const reason = ref('');

// Fluxo de pedido: NÃO emite 'confirm' (nada foi assumido, o ReplyBox não pode
// reenviar), NÃO dispara confetti (não houve takeover) e NÃO chama assignTeam
// (mudar o time da conversa DE OUTRA PESSOA antes da aprovação é efeito colateral
// não autorizado).
const onRequestTakeover = async () => {
  isLoading.value = true;
  errorMessage.value = '';
  try {
    await store.dispatch('takeoverRequests/create', {
      conversationId: currentChat.value.id,
      reason: reason.value?.trim() || undefined,
    });
    useAlert(t('CONVERSATION.TAKEOVER_REQUEST.SENT'));
    hide();
  } catch (error) {
    const code = error?.response?.data?.error_code;
    const generic = t('CONVERSATION.REPLY_GATE_DIALOG.ERROR');
    // vue-i18n 9 devolve a própria chave quando falta (o `{ default }` de 2 args é
    // ignorado) — detectamos ausência por igualdade em vez de exibir a chave crua.
    const key =
      code && `CONVERSATION.TAKEOVER_REQUEST.ERRORS.${code.toUpperCase()}`;
    const translated = key && t(key);
    errorMessage.value =
      translated && translated !== key ? translated : generic;
  } finally {
    isLoading.value = false;
  }
};

const onConfirm = async () => {
  if (isRequestFlow.value) {
    await onRequestTakeover();
    return;
  }

  isLoading.value = true;
  errorMessage.value = '';
  try {
    if (needsTeamSelection.value && selectedTeamId.value) {
      await store.dispatch('assignTeam', {
        conversationId: currentChat.value.id,
        teamId: selectedTeamId.value,
        rethrow: true,
      });
    }
    await store.dispatch('assignAgent', {
      conversationId: currentChat.value.id,
      agentId: currentUser.value.id,
      rethrow: true,
    });
    // celebração sutil só na 1ª assunção da sessão (lazy, reduced-motion safe).
    fireTakeoverConfetti();
    hide();
    emit('confirm'); // ReplyBox reenvia a mensagem digitada
  } catch (error) {
    errorMessage.value = t('CONVERSATION.REPLY_GATE_DIALOG.ERROR');
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="md"
    :title="dialogTitle"
    :description="dialogDescription"
    :confirm-button-label="confirmLabel"
    :cancel-button-label="$t('CONVERSATION.REPLY_GATE_DIALOG.CANCEL')"
    :is-loading="isLoading"
    :disable-confirm-button="!canConfirm || isLoading"
    @confirm="onConfirm"
  >
    <Motion
      as="div"
      class="flex flex-col gap-3"
      :initial="{ opacity: 0, y: 24 }"
      :animate="{ opacity: 1, y: 0 }"
      :transition="{ type: 'spring', visualDuration: 0.35, bounce: 0.25 }"
    >
      <!-- card do dono atual (Avatar + nome + badge IA) -->
      <div
        v-if="assigneeInfo"
        class="flex items-center gap-3 rounded-lg bg-n-alpha-2 p-3"
      >
        <Avatar :name="assigneeInfo.name" :size="32" />
        <span class="text-sm font-medium text-n-slate-12">
          {{ assigneeInfo.name }}
        </span>
        <span
          v-if="assigneeInfo.isAI"
          class="inline-flex items-center gap-1 rounded-md bg-n-brand/10 px-1.5 py-0.5 text-xs font-medium text-n-brand"
        >
          <span class="i-lucide-sparkles size-3" />
          {{ $t('CONVERSATION.REPLY_GATE_DIALOG.AI_BADGE') }}
        </span>
      </div>

      <!-- Fluxo de pedido (gate ON + dono humano): motivo opcional. Sem seleção
           de time — mudar o time da conversa de outra pessoa não é permitido. -->
      <div v-if="isRequestFlow" class="flex flex-col gap-2">
        <label class="text-sm text-n-slate-11" for="takeover-reason">
          {{ $t('CONVERSATION.TAKEOVER_REQUEST.REASON_LABEL') }}
        </label>
        <textarea
          id="takeover-reason"
          v-model="reason"
          rows="2"
          class="reset-base w-full resize-none rounded-lg border border-n-weak bg-n-alpha-1 p-2 text-sm text-n-slate-12"
          :placeholder="$t('CONVERSATION.TAKEOVER_REQUEST.REASON_PLACEHOLDER')"
        />
      </div>

      <!-- variante (d) / DD-5: select dos times DO usuário (NUNCA todos) -->
      <div
        v-if="needsTeamSelection && !isRequestFlow"
        class="flex flex-col gap-2"
      >
        <span class="text-sm text-n-slate-11">
          {{ $t('CONVERSATION.REPLY_GATE_DIALOG.TEAM_LABEL') }}
        </span>
        <label
          v-for="team in myTeams"
          :key="team.id"
          class="flex cursor-pointer items-center gap-2 rounded-lg border p-3"
          :class="
            selectedTeamId === team.id
              ? 'border-n-brand bg-n-brand/5'
              : 'border-n-weak'
          "
        >
          <input
            v-model="selectedTeamId"
            type="radio"
            :value="team.id"
            class="accent-n-brand"
          />
          <span class="text-sm font-medium text-n-slate-12">
            {{ team.name }}
          </span>
        </label>
        <span v-if="!myTeams.length" class="text-sm text-n-slate-10">
          {{ $t('CONVERSATION.REPLY_GATE_DIALOG.NO_TEAMS') }}
        </span>
      </div>

      <span v-if="errorMessage" class="text-sm text-n-ruby-11">
        {{ errorMessage }}
      </span>
    </Motion>
  </Dialog>
</template>
