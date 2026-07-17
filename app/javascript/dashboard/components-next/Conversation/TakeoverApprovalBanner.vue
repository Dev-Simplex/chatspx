<script setup>
// D1 (Fase 3) — superfície DURÁVEL de aprovação: banner no topo da conversa
// ("Fulano pediu esta conversa: '…' [Aprovar] [Negar]"). O sino NÃO serve de CTA
// (RemoveDuplicateNotificationJob apaga o aviso na próxima mensagem), por isso a
// aprovação mora aqui + na lista "Pedidos".
//
// Auto-suficiente: lê o store direto (só precisa da conversa atual). Só aparece
// para o DONO da conversa quando há pedido pendente.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();

const currentChat = useMapGetter('getSelectedChat');
const currentUserId = useMapGetter('getCurrentUserID');
const getPending = useMapGetter('takeoverRequests/getPendingForConversation');

// currentChat.id é o display_id (é o que o pedido guarda em conversationId).
const conversationId = computed(() => currentChat.value?.id ?? null);

const amOwner = computed(() => {
  const assignee = currentChat.value?.meta?.assignee;
  return Boolean(assignee && assignee.id === currentUserId.value);
});

const pendingRequests = computed(() => {
  if (!conversationId.value || !amOwner.value) return [];
  return getPending.value(conversationId.value);
});

// Mostra o mais antigo; se houver mais de um, avisa (aprovar um supersede os
// outros no backend, na mesma transação).
const activeRequest = computed(() => pendingRequests.value[0] ?? null);
const extraCount = computed(() =>
  Math.max(0, pendingRequests.value.length - 1)
);

const requesterName = computed(
  () =>
    activeRequest.value?.requester?.name ||
    t('CONVERSATION.TAKEOVER_APPROVAL.SOMEONE')
);

// aspas/travessão em JS: o lint proíbe string literal solta no <template>.
const quotedReason = computed(() =>
  activeRequest.value?.reason ? `— “${activeRequest.value.reason}”` : ''
);

const isLoading = ref(false);

const resolve = async action => {
  if (!activeRequest.value || isLoading.value) return;
  isLoading.value = true;
  try {
    await store.dispatch(`takeoverRequests/${action}`, {
      id: activeRequest.value.id,
    });
    useAlert(
      t(
        action === 'approve'
          ? 'CONVERSATION.TAKEOVER_APPROVAL.APPROVED'
          : 'CONVERSATION.TAKEOVER_APPROVAL.DENIED'
      )
    );
  } catch (error) {
    const code = error?.response?.data?.error_code;
    useAlert(
      code === 'takeover_request_closed'
        ? t('CONVERSATION.TAKEOVER_APPROVAL.ALREADY_CLOSED')
        : t('CONVERSATION.TAKEOVER_APPROVAL.ERROR')
    );
    // Já respondido por outra aba/pessoa → refaz a lista p/ o banner sumir.
    store.dispatch('takeoverRequests/fetchIncoming');
  } finally {
    isLoading.value = false;
  }
};

// Ao trocar de conversa (e ao montar), busca meus pedidos pendentes — assim o
// banner aparece mesmo sem o realtime ter disparado nesta sessão.
watch(
  conversationId,
  id => {
    if (id) store.dispatch('takeoverRequests/fetchIncoming');
  },
  { immediate: true }
);
</script>

<template>
  <div
    v-if="activeRequest"
    class="mx-2 mt-2 flex flex-col gap-2 rounded-lg border border-n-amber-5/40 bg-n-amber-3 px-3 py-2 relative z-10 sm:flex-row sm:items-center sm:justify-between"
  >
    <div class="flex items-center gap-2 min-w-0 text-sm text-n-amber-12">
      <span class="i-lucide-hand size-4 shrink-0 text-n-amber-11" />
      <span class="min-w-0">
        <span class="font-medium">{{ requesterName }}</span>
        {{ ' ' }}
        <span>{{ t('CONVERSATION.TAKEOVER_APPROVAL.WANTS_THIS') }}</span>
        <span v-if="quotedReason" class="italic text-n-amber-11">
          {{ quotedReason }}
        </span>
        <span v-if="extraCount" class="text-n-amber-11">
          {{ ' ' }}({{
            t('CONVERSATION.TAKEOVER_APPROVAL.AND_MORE', { count: extraCount })
          }})
        </span>
      </span>
    </div>
    <div class="flex items-center gap-2 shrink-0">
      <Button
        size="sm"
        variant="ghost"
        color="slate"
        :is-loading="isLoading"
        :label="t('CONVERSATION.TAKEOVER_APPROVAL.DENY')"
        @click="resolve('deny')"
      />
      <Button
        size="sm"
        color="blue"
        :is-loading="isLoading"
        :label="t('CONVERSATION.TAKEOVER_APPROVAL.APPROVE')"
        @click="resolve('approve')"
      />
    </div>
  </div>
</template>
