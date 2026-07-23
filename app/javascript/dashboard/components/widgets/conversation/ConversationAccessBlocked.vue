<script setup>
// Isolamento de acesso por agente (flag agent_conversation_isolation por inbox):
// quando o agente abre uma conversa que não é dele, o backend devolve 403
// 'conversation_access_blocked' e este painel aparece no lugar das mensagens —
// avisa de quem é a conversa e oferece "Solicitar atendimento" (reusa o fluxo do
// takeover). A conversa continua aparecendo na busca/lista; o bloqueio é só aqui.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  meta: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const store = useStore();
const { currentAccount } = useAccount();

const gateEnabled = computed(() =>
  Boolean(currentAccount.value?.settings?.takeover_request_gate)
);

const ownerName = computed(() => props.meta?.current_assignee?.name || '');
const teamName = computed(() => props.meta?.team?.name || '');

const requested = ref(Boolean(props.meta?.existing_request));
const isRequesting = ref(false);
// Mensagem curta e opcional para o dono — limitada p/ não virar textão.
const reason = ref('');
const REASON_MAX = 140;

const description = computed(() =>
  teamName.value
    ? t('CONVERSATION.ACCESS_BLOCKED.BODY_WITH_TEAM', {
        name: ownerName.value,
        team: teamName.value,
      })
    : t('CONVERSATION.ACCESS_BLOCKED.BODY', { name: ownerName.value })
);

const onRequest = async () => {
  if (isRequesting.value) return;
  isRequesting.value = true;
  try {
    await store.dispatch('takeoverRequests/create', {
      conversationId: props.conversationId,
      reason: reason.value.trim() || undefined,
    });
    requested.value = true;
    useAlert(t('CONVERSATION.TAKEOVER_REQUEST.SENT'));
  } catch (error) {
    const code = error?.response?.data?.error_code;
    useAlert(
      code === 'takeover_request_exists'
        ? t('CONVERSATION.ACCESS_BLOCKED.REQUEST_EXISTS')
        : t('CONVERSATION.ACCESS_BLOCKED.REQUEST_ERROR')
    );
  } finally {
    isRequesting.value = false;
  }
};
</script>

<template>
  <div
    class="flex flex-col items-center justify-center flex-1 w-full h-full px-6 text-center bg-n-chat-bg"
  >
    <div
      class="flex items-center justify-center rounded-full size-14 bg-n-alpha-2 text-n-slate-11"
    >
      <span class="i-lucide-lock-keyhole size-7" />
    </div>
    <h3 class="mt-4 text-base font-medium text-n-slate-12">
      {{ $t('CONVERSATION.ACCESS_BLOCKED.TITLE') }}
    </h3>
    <p class="mt-1 max-w-md text-sm text-n-slate-11">{{ description }}</p>

    <span v-if="requested" class="mt-5 text-sm font-medium text-n-slate-11">
      {{ $t('CONVERSATION.ACCESS_BLOCKED.REQUEST_SENT') }}
    </span>
    <template v-else-if="gateEnabled">
      <p class="mt-1 max-w-md text-sm text-n-slate-11">
        {{ $t('CONVERSATION.ACCESS_BLOCKED.ACTION_HINT') }}
      </p>
      <div class="relative w-full mt-5 max-w-sm">
        <textarea
          v-model="reason"
          :maxlength="REASON_MAX"
          rows="2"
          class="reset-base w-full px-3 py-2 text-sm text-left rounded-lg resize-none bg-n-alpha-2 border border-n-weak text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-n-brand"
          :placeholder="$t('CONVERSATION.ACCESS_BLOCKED.REASON_PLACEHOLDER')"
        />
        <span
          v-if="reason.length"
          class="absolute text-xs bottom-1.5 ltr:right-2 rtl:left-2 text-n-slate-10"
        >
          {{ `${reason.length}/${REASON_MAX}` }}
        </span>
      </div>
      <Button
        color="amber"
        size="sm"
        class="mt-3"
        :is-loading="isRequesting"
        :disabled="isRequesting"
        :label="$t('CONVERSATION.ACCESS_BLOCKED.REQUEST')"
        @click="onRequest"
      />
    </template>
  </div>
</template>
