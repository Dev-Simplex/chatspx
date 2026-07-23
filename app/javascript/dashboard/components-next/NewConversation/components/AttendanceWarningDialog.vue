<script setup>
// Aviso "este contato já está em atendimento" ao criar conversa (Fase 2).
// Hoje o ComposeConversation reusa a conversa existente CALADO — o agente acha
// que abriu um atendimento novo e na verdade escreveu no meio do atendimento de
// um colega. Este diálogo é o momento em que o sistema para de mentir.
//
// Sem a Fase 3 (pedido/aprovação) as ações são: Ir para a conversa / Enviar
// mesmo assim / Cancelar. O valor — parar de mandar mensagem calado — não
// depende de pedido nenhum. O botão "Solicitar atendimento" entra aqui na Fase 3.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { ATTENDANCE_VARIANT } from 'dashboard/composables/useAttendanceGate';

const props = defineProps({
  variant: { type: String, default: ATTENDANCE_VARIANT.HUMAN },
  attendance: { type: Object, default: null },
  sameInbox: { type: Boolean, default: false },
  // Com o modo de pedido ligado, o pai (ComposeConversation) manda estas 3:
  // pode solicitar → mostra "Solicitar atendimento"; já pedi → mostra "Pedido
  // enviado"; e allowSendAnyway=false esconde o "Enviar mesmo assim" (validação
  // de verdade em vez de aviso furável).
  canRequest: { type: Boolean, default: false },
  hasPendingRequest: { type: Boolean, default: false },
  allowSendAnyway: { type: Boolean, default: true },
  isRequesting: { type: Boolean, default: false },
  // 'compose' (default) = criar conversa; 'conversation' = dropdown de responsável
  // dentro de uma conversa (reusa o copy CONVERSATION.TAKEOVER_REQUEST.*, que fala
  // em "assumir esta conversa" em vez de "enviar").
  context: { type: String, default: 'compose' },
});

const emit = defineEmits([
  'goToConversation',
  'sendAnyway',
  'requestAttendance',
  'cancel',
]);

const { t } = useI18n();
const dialogRef = ref(null);
// Mensagem curta e opcional para o dono (limitada p/ não virar textão).
const reason = ref('');
const REASON_MAX = 140;

const ownerName = computed(
  () =>
    props.attendance?.assignee?.availableName ||
    props.attendance?.assignee?.name ||
    ''
);
const teamName = computed(() => props.attendance?.team?.name || '');
const inboxName = computed(() => props.attendance?.inbox?.name || '');

const title = computed(() =>
  props.context === 'conversation'
    ? t('CONVERSATION.TAKEOVER_REQUEST.TITLE')
    : t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.TITLE')
);

const description = computed(() => {
  if (props.context === 'conversation') {
    return t('CONVERSATION.TAKEOVER_REQUEST.DESC', { name: ownerName.value });
  }
  if (props.variant === ATTENDANCE_VARIANT.UNKNOWN) {
    return t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.BODY_UNKNOWN');
  }
  if (props.variant === ATTENDANCE_VARIANT.BOT) {
    return t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.BODY_BOT', {
      name: ownerName.value,
    });
  }
  if (props.variant === ATTENDANCE_VARIANT.UNASSIGNED) {
    return t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.BODY_UNASSIGNED');
  }
  return teamName.value
    ? t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.BODY_HUMAN_WITH_TEAM', {
        name: ownerName.value,
        team: teamName.value,
      })
    : t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.BODY_HUMAN', {
        name: ownerName.value,
      });
});

// "nesta caixa" vs "em outra caixa ({nome})": o atendimento pode estar em OUTRA
// inbox — que é justamente a duplicação que o código antigo não via.
const inboxHint = computed(() => {
  // No dropdown da conversa não há noção de "outra caixa" — o pedido é sobre ESTA
  // conversa.
  if (props.context === 'conversation') return '';
  if (props.variant === ATTENDANCE_VARIANT.UNKNOWN || !inboxName.value) {
    return '';
  }
  return props.sameInbox
    ? t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.SAME_INBOX')
    : t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.OTHER_INBOX', {
        inbox: inboxName.value,
      });
});

// Só oferece "Ir para a conversa" se eu REALMENTE alcanço (canOpen do endpoint) —
// senão levaria a um 403 de outro time. undefined (compose antigo) = permite.
const canGoToConversation = computed(
  () =>
    props.variant !== ATTENDANCE_VARIANT.UNKNOWN &&
    !!props.attendance?.id &&
    props.attendance?.canOpen !== false
);

// Zera o recado a cada abertura — o diálogo é uma instância persistente
// (open/close), então sem isto o texto de uma tentativa vazaria p/ a próxima.
const open = () => {
  reason.value = '';
  dialogRef.value?.open();
};
const close = () => dialogRef.value?.close();

defineExpose({ open, close });
</script>

<template>
  <Dialog ref="dialogRef" type="edit" :title="title" @close="emit('cancel')">
    <div class="flex flex-col gap-2">
      <p class="text-sm text-n-slate-11">{{ description }}</p>
      <p v-if="inboxHint" class="text-sm text-n-slate-10">{{ inboxHint }}</p>
      <!-- Recado curto ao dono, só no fluxo de pedir (canRequest, sem pendente). -->
      <div v-if="canRequest && !hasPendingRequest" class="relative mt-1">
        <textarea
          v-model="reason"
          :maxlength="REASON_MAX"
          rows="2"
          class="reset-base w-full px-3 py-2 text-sm rounded-lg resize-none bg-n-alpha-2 border border-n-weak text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-n-brand"
          :placeholder="
            t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.REASON_PLACEHOLDER')
          "
        />
        <span
          v-if="reason.length"
          class="absolute text-xs bottom-1.5 ltr:right-2 rtl:left-2 text-n-slate-10"
        >
          {{ `${reason.length}/${REASON_MAX}` }}
        </span>
      </div>
    </div>

    <!-- type="button" OBRIGATÓRIO: este rodapé vive dentro do <form> do Dialog e
         o Button não define type — sem isso todo clique viraria submit e
         dispararia o confirm do Dialog por cima do handler certo. -->
    <template #footer>
      <div class="flex flex-wrap items-center justify-end gap-2">
        <Button
          type="button"
          variant="ghost"
          color="slate"
          size="sm"
          :label="t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.CANCEL')"
          @click="emit('cancel')"
        />
        <!-- "Enviar mesmo assim" só quando o modo NÃO exige pedido (aviso furável
             de sempre). Com o modo ligado + dono humano, some: a saída é pedir. -->
        <Button
          v-if="allowSendAnyway"
          type="button"
          variant="faded"
          color="slate"
          size="sm"
          :label="t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.SEND_ANYWAY')"
          @click="emit('sendAnyway')"
        />
        <Button
          v-if="canGoToConversation"
          type="button"
          variant="faded"
          color="slate"
          size="sm"
          :label="
            t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.GO_TO_CONVERSATION')
          "
          @click="emit('goToConversation')"
        />
        <!-- Já pedi: só o aviso, sem botão. -->
        <span v-if="hasPendingRequest" class="text-sm text-n-slate-11">
          {{ t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.REQUEST_SENT') }}
        </span>
        <!-- Ação primária no modo ligado: solicitar o atendimento ao dono. -->
        <!-- Cor de atenção (âmbar) só no fluxo de "Todos os contatos" (compose);
             no dropdown da conversa segue verde. -->
        <Button
          v-else-if="canRequest"
          type="button"
          :color="context === 'conversation' ? 'blue' : 'amber'"
          size="sm"
          :is-loading="isRequesting"
          :disabled="isRequesting"
          :label="t('COMPOSE_NEW_CONVERSATION.ATTENDANCE_WARNING.REQUEST')"
          @click="emit('requestAttendance', reason.trim() || undefined)"
        />
      </div>
    </template>
  </Dialog>
</template>
