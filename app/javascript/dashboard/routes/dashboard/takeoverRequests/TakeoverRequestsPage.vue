<script setup>
// D1 (Fase 3) — superfície DURÁVEL "Pedidos": lista os pedidos de atendimento
// que EU (dono) preciso responder. Existe porque o sino não serve de CTA
// (RemoveDuplicateNotificationJob apaga o aviso na próxima mensagem da conversa).
import { onMounted, computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountId } = useAccount();

const requests = useMapGetter('takeoverRequests/getIncoming');
const uiFlags = useMapGetter('takeoverRequests/getUIFlags');
const isFetching = computed(() => uiFlags.value.isFetching);
const resolvingId = ref(null);

const fetchRequests = () => store.dispatch('takeoverRequests/fetchIncoming');

const resolve = async (request, action) => {
  if (resolvingId.value) return;
  resolvingId.value = request.id;
  try {
    await store.dispatch(`takeoverRequests/${action}`, { id: request.id });
    useAlert(
      t(
        action === 'approve'
          ? 'TAKEOVER_REQUESTS.APPROVED'
          : 'TAKEOVER_REQUESTS.DENIED'
      )
    );
  } catch {
    useAlert(t('TAKEOVER_REQUESTS.ERROR'));
    fetchRequests();
  } finally {
    resolvingId.value = null;
  }
};

// aspas em JS: o lint proíbe string literal solta no <template>.
const quotedReason = reason => (reason ? `“${reason}”` : '');

const goToConversation = request => {
  if (!request.conversationId) return;
  router.push(
    `/app/accounts/${accountId.value}/conversations/${request.conversationId}`
  );
};

onMounted(fetchRequests);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6">
      <div
        class="flex items-center justify-between w-full py-6 mx-auto max-w-5xl"
      >
        <span class="text-xl font-medium truncate text-n-slate-12">
          {{ t('TAKEOVER_REQUESTS.TITLE') }}
        </span>
      </div>
    </header>

    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full mx-auto max-w-5xl">
        <div
          v-if="isFetching && !requests.length"
          class="flex items-center justify-center py-10 text-n-slate-11"
        >
          <Spinner />
        </div>
        <div
          v-else-if="!requests.length"
          class="flex items-center justify-center py-10"
        >
          <span class="text-base text-n-slate-11">
            {{ t('TAKEOVER_REQUESTS.EMPTY') }}
          </span>
        </div>
        <div v-else class="flex flex-col gap-3 pt-4 pb-6">
          <div
            v-for="request in requests"
            :key="request.id"
            class="flex flex-col w-full gap-3 p-4 border border-n-weak rounded-xl bg-n-solid-1 sm:flex-row sm:items-center sm:justify-between"
          >
            <div class="flex items-center gap-3 min-w-0">
              <Avatar
                :name="request.requester?.name || '?'"
                :src="request.requester?.thumbnail"
                :size="36"
                rounded-full
              />
              <div class="flex flex-col min-w-0">
                <span class="text-sm text-n-slate-12">
                  <span class="font-medium">{{ request.requester?.name }}</span>
                  {{ ' ' }}{{ t('TAKEOVER_REQUESTS.WANTS') }}
                  <button
                    type="button"
                    class="font-medium text-n-brand hover:underline"
                    @click="goToConversation(request)"
                  >
                    {{
                      request.contact?.name ||
                      t('TAKEOVER_REQUESTS.A_CONVERSATION')
                    }}
                  </button>
                </span>
                <span
                  v-if="request.reason"
                  class="text-xs italic truncate text-n-slate-11"
                >
                  {{ quotedReason(request.reason) }}
                </span>
              </div>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <Button
                size="sm"
                variant="ghost"
                color="slate"
                :is-loading="resolvingId === request.id"
                :label="t('TAKEOVER_REQUESTS.DENY')"
                @click="resolve(request, 'deny')"
              />
              <Button
                size="sm"
                color="blue"
                :is-loading="resolvingId === request.id"
                :label="t('TAKEOVER_REQUESTS.APPROVE')"
                @click="resolve(request, 'approve')"
              />
            </div>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>
