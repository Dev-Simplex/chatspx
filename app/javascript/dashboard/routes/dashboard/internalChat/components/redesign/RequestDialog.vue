<script setup>
import { ref, computed, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

// Formulário curto do "Pedir aprovação" / "Pedir ajuda". Envia direto pelo
// store; só fecha quando o cartão volta do servidor (senão mostra o erro).
const props = defineProps({
  channelId: { type: Number, default: null },
  // Quem pode aprovar: os outros membros da conversa [{ id, name, avatar_url }].
  approvers: { type: Array, default: () => [] },
});

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const titleRef = ref(null);
const kind = ref('approval');
const title = ref('');
const detail = ref('');
const approverId = ref(null);
const conversationId = ref('');
const sending = ref(false);

const isApproval = computed(() => kind.value === 'approval');
const canSend = computed(
  () =>
    Boolean(title.value.trim()) &&
    (!isApproval.value || Boolean(approverId.value)) &&
    !sending.value
);

const open = requestKind => {
  kind.value = requestKind;
  title.value = '';
  detail.value = '';
  conversationId.value = '';
  // Numa DM só há uma pessoa: já vem escolhida.
  approverId.value =
    props.approvers.length === 1 ? props.approvers[0].id : null;
  dialogRef.value?.open();
  nextTick(() => titleRef.value?.focus());
};

const send = async () => {
  if (!canSend.value) return;
  sending.value = true;
  try {
    await store.dispatch('internalChat/sendRequest', {
      channelId: props.channelId,
      kind: kind.value,
      title: title.value.trim(),
      detail: detail.value.trim(),
      approverId: isApproval.value ? approverId.value : null,
      conversationId: conversationId.value.replace(/\D/g, '') || null,
    });
    dialogRef.value?.close();
  } catch (e) {
    useAlert(t('INTERNAL_CHAT.REQUEST.FORM.FAILED'));
  } finally {
    sending.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      isApproval
        ? t('INTERNAL_CHAT.REQUEST.FORM.TITLE_APPROVAL')
        : t('INTERNAL_CHAT.REQUEST.FORM.TITLE_HELP')
    "
    :description="
      isApproval
        ? t('INTERNAL_CHAT.REQUEST.FORM.DESCRIPTION_APPROVAL')
        : t('INTERNAL_CHAT.REQUEST.FORM.DESCRIPTION_HELP')
    "
    :confirm-button-label="
      isApproval
        ? t('INTERNAL_CHAT.REQUEST.FORM.SEND_APPROVAL')
        : t('INTERNAL_CHAT.REQUEST.FORM.SEND_HELP')
    "
    :cancel-button-label="t('INTERNAL_CHAT.REQUEST.FORM.CANCEL')"
    :disable-confirm-button="!canSend"
    :is-loading="sending"
    width="md"
    @confirm="send"
  >
    <div class="flex flex-col gap-4">
      <label class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{
            isApproval
              ? t('INTERNAL_CHAT.REQUEST.FORM.WHAT_APPROVAL')
              : t('INTERNAL_CHAT.REQUEST.FORM.WHAT_HELP')
          }}
        </span>
        <input
          ref="titleRef"
          v-model="title"
          type="text"
          maxlength="140"
          :placeholder="
            isApproval
              ? t('INTERNAL_CHAT.REQUEST.FORM.WHAT_PLACEHOLDER_APPROVAL')
              : t('INTERNAL_CHAT.REQUEST.FORM.WHAT_PLACEHOLDER_HELP')
          "
          class="reset-base w-full px-3 py-2 text-sm border rounded-lg outline-none bg-n-solid-1 dark:bg-n-solid-2 border-n-strong text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-teal-9"
        />
      </label>

      <label class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.REQUEST.FORM.DETAIL') }}
        </span>
        <textarea
          v-model="detail"
          rows="2"
          maxlength="1000"
          :placeholder="t('INTERNAL_CHAT.REQUEST.FORM.DETAIL_PLACEHOLDER')"
          class="reset-base w-full px-3 py-2 text-sm border rounded-lg outline-none resize-none bg-n-solid-1 dark:bg-n-solid-2 border-n-strong text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-teal-9"
        />
      </label>

      <div v-if="isApproval" class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.REQUEST.FORM.APPROVER') }}
        </span>
        <p
          v-if="!approvers.length"
          class="mb-0 px-3 py-2 text-sm rounded-lg bg-n-amber-3 text-n-amber-12"
        >
          {{ t('INTERNAL_CHAT.REQUEST.FORM.APPROVER_EMPTY') }}
        </p>
        <div v-else class="flex flex-col gap-1 overflow-y-auto max-h-44">
          <button
            v-for="person in approvers"
            :key="person.id"
            type="button"
            class="flex items-center gap-2.5 px-2.5 py-1.5 text-sm text-left border rounded-lg text-n-slate-12"
            :class="
              approverId === person.id
                ? 'border-n-teal-9 bg-n-teal-9/10'
                : 'border-n-weak hover:bg-n-alpha-1'
            "
            :aria-pressed="approverId === person.id"
            @click="approverId = person.id"
          >
            <Avatar
              :name="person.name || ''"
              :src="person.avatar_url || ''"
              :size="24"
              rounded-full
            />
            <span class="flex-1 min-w-0 truncate">{{ person.name }}</span>
            <span
              v-if="approverId === person.id"
              class="flex-shrink-0 i-lucide-check size-4 text-n-teal-11"
            />
          </button>
        </div>
      </div>

      <label class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.REQUEST.FORM.CONVERSATION') }}
        </span>
        <input
          v-model="conversationId"
          type="text"
          inputmode="numeric"
          :placeholder="
            t('INTERNAL_CHAT.REQUEST.FORM.CONVERSATION_PLACEHOLDER')
          "
          class="reset-base w-full px-3 py-2 text-sm border rounded-lg outline-none bg-n-solid-1 dark:bg-n-solid-2 border-n-strong text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-teal-9"
        />
      </label>
    </div>
  </Dialog>
</template>
