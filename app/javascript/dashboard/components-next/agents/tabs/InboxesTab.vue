<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const assistantId = computed(() => Number(route.params.assistantId));
const connectedInboxes = computed(
  () => store.getters['captainInboxes/getRecords']
);
const isFetching = computed(
  () => store.getters['captainInboxes/getUIFlags'].isFetching
);

const allInboxes = computed(() => store.getters['inboxes/getInboxes']);
const availableInboxes = computed(() => {
  const connectedIds = connectedInboxes.value.map(i => i.id);
  return allInboxes.value.filter(i => !connectedIds.includes(i.id));
});

const showConnect = ref(false);
const selectedInboxId = ref(null);

onMounted(() => {
  store.dispatch('captainInboxes/get', { assistantId: assistantId.value });
  store.dispatch('inboxes/get');
});

async function connectInbox() {
  if (!selectedInboxId.value) return;
  await store.dispatch('captainInboxes/create', {
    assistantId: assistantId.value,
    inboxId: selectedInboxId.value,
  });
  selectedInboxId.value = null;
  showConnect.value = false;
  store.dispatch('captainInboxes/get', { assistantId: assistantId.value });
}

async function disconnectInbox(inboxId) {
  await store.dispatch('captainInboxes/delete', {
    assistantId: assistantId.value,
    inboxId,
  });
}

const CHANNEL_ICONS = {
  'Channel::WebWidget': 'i-lucide-globe',
  'Channel::Api': 'i-lucide-zap',
  'Channel::WhatsApp': 'i-lucide-smartphone',
  'Channel::Email': 'i-lucide-mail',
  'Channel::Telegram': 'i-lucide-send',
  'Channel::FacebookPage': 'i-lucide-user',
};

function channelIcon(channelType) {
  return CHANNEL_ICONS[channelType] || 'i-lucide-inbox';
}
</script>

<template>
  <div class="p-6">
    <div class="mb-4 flex items-center justify-between">
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{ t('AGENT_DETAIL.TABS.INBOXES') }}
      </h3>
      <button
        type="button"
        class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white transition-colors hover:brightness-95"
        @click="showConnect = !showConnect"
      >
        <i class="i-lucide-plus size-3.5" />
        {{ t('CAPTAIN.AGENT_TABS.INBOXES.CONNECT') }}
      </button>
    </div>

    <!-- Connect form -->
    <div
      v-if="showConnect"
      class="mb-4 flex gap-2 rounded-xl border border-n-weak bg-white p-4 dark:bg-n-solid-2"
    >
      <select
        v-model="selectedInboxId"
        class="flex-1 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none transition-colors focus:border-n-brand focus:ring-1 focus:ring-n-brand dark:bg-n-solid-3"
      >
        <option :value="null" disabled>
          {{ t('CAPTAIN.AGENT_TABS.INBOXES.SELECT_INBOX') }}
        </option>
        <option
          v-for="inbox in availableInboxes"
          :key="inbox.id"
          :value="inbox.id"
        >
          {{ inbox.name }}
        </option>
      </select>
      <button
        type="button"
        class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white transition-colors hover:brightness-95"
        @click="connectInbox"
      >
        {{ t('CAPTAIN.AGENT_TABS.INBOXES.CONNECT_BTN') }}
      </button>
    </div>

    <div
      v-if="isFetching"
      class="flex items-center gap-2 text-sm text-n-slate-10"
    >
      <i class="i-lucide-loader-2 size-3.5 animate-spin" />
      {{ t('CAPTAIN.AGENT_TABS.INBOXES.LOADING') }}
    </div>
    <div v-else-if="!connectedInboxes.length" class="py-16 text-center">
      <i class="i-lucide-inbox mx-auto mb-4 size-12 text-n-slate-9" />
      <p class="text-base font-medium text-n-slate-12">
        {{ t('CAPTAIN.AGENT_TABS.INBOXES.NO_INBOXES') }}
      </p>
    </div>

    <div v-else class="space-y-3">
      <div
        v-for="inbox in connectedInboxes"
        :key="inbox.id"
        class="flex items-center justify-between rounded-xl border border-n-weak bg-white p-4 transition-shadow duration-200 hover:shadow-md dark:bg-n-solid-2"
      >
        <div class="flex items-center gap-3">
          <div
            class="flex size-8 items-center justify-center rounded-lg bg-n-alpha-2"
          >
            <i
              class="size-4 text-n-slate-11"
              :class="channelIcon(inbox.channel_type)"
            />
          </div>
          <div>
            <p class="text-sm font-medium text-n-slate-12">
              {{ inbox.name }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{ inbox.channel_type }}
            </p>
          </div>
        </div>
        <button
          type="button"
          class="rounded-lg p-2 text-n-slate-10 transition-colors hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-900/20 dark:hover:text-red-400"
          @click="disconnectInbox(inbox.id)"
        >
          <i class="i-lucide-unlink size-3.5" />
        </button>
      </div>
    </div>
  </div>
</template>
