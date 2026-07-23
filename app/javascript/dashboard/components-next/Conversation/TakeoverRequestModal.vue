<script setup>
// D1 (Fase 3) — modal PROATIVO para o DONO: quando chega um pedido de atendimento
// (realtime, sou o dono), abre um modal com quem pediu, a conversa e o recado, e
// deixa Aprovar na hora ou "Ainda não" (adia — o pedido segue pendente, o dono
// decide depois pelo banner/lista). Renderless global (montado no Dashboard.vue,
// como o TakeoverResolutionToaster).
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();
const incoming = useMapGetter('takeoverRequests/getIncomingRequest');

const dialogRef = ref(null);
const isLoading = ref(false);

watch(incoming, value => {
  if (value) dialogRef.value?.open();
  else dialogRef.value?.close();
});

const requesterName = computed(
  () =>
    incoming.value?.requesterName || t('CONVERSATION.TAKEOVER_INCOMING.SOMEONE')
);
const contactName = computed(() => incoming.value?.contactName || '');
const reason = computed(() => incoming.value?.reason || '');

const description = computed(() =>
  contactName.value
    ? t('CONVERSATION.TAKEOVER_INCOMING.BODY_WITH_CONTACT', {
        name: requesterName.value,
        contact: contactName.value,
      })
    : t('CONVERSATION.TAKEOVER_INCOMING.BODY', { name: requesterName.value })
);

const dismiss = () => store.dispatch('takeoverRequests/clearIncomingRequest');

const onApprove = async () => {
  const req = incoming.value;
  if (!req || isLoading.value) return;
  isLoading.value = true;
  try {
    await store.dispatch('takeoverRequests/approve', { id: req.id });
    useAlert(t('CONVERSATION.TAKEOVER_APPROVAL.APPROVED'));
    dismiss();
  } catch (error) {
    const code = error?.response?.data?.error_code;
    useAlert(
      code === 'takeover_request_closed'
        ? t('CONVERSATION.TAKEOVER_APPROVAL.ALREADY_CLOSED')
        : t('CONVERSATION.TAKEOVER_APPROVAL.ERROR')
    );
    dismiss();
    store.dispatch('takeoverRequests/fetchIncoming');
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="t('CONVERSATION.TAKEOVER_INCOMING.TITLE')"
    :show-confirm-button="false"
    @close="dismiss"
  >
    <div class="flex flex-col gap-2">
      <p class="text-sm text-n-slate-11">{{ description }}</p>
      <p
        v-if="reason"
        class="px-3 py-2 text-sm italic rounded-lg text-n-slate-12 bg-n-alpha-2"
      >
        {{ `“${reason}”` }}
      </p>
    </div>

    <!-- type="button": o rodapé vive dentro do <form> do Dialog; sem isso o clique
         viraria submit/confirm. -->
    <template #footer>
      <div class="flex items-center justify-end gap-2">
        <Button
          type="button"
          variant="ghost"
          color="slate"
          size="sm"
          :label="t('CONVERSATION.TAKEOVER_INCOMING.LATER')"
          @click="dismiss"
        />
        <Button
          type="button"
          color="blue"
          size="sm"
          :is-loading="isLoading"
          :disabled="isLoading"
          :label="t('CONVERSATION.TAKEOVER_INCOMING.APPROVE')"
          @click="onApprove"
        />
      </div>
    </template>
  </Dialog>
</template>
