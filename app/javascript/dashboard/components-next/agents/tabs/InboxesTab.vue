<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';

import AiButton from 'dashboard/components-next/agents-ui/AiButton.vue';
import AiCard from 'dashboard/components-next/agents-ui/AiCard.vue';
import AiSelect from 'dashboard/components-next/agents-ui/AiSelect.vue';
import AiEmptyState from 'dashboard/components-next/agents-ui/AiEmptyState.vue';
import AiDropdown from 'dashboard/components-next/agents-ui/AiDropdown.vue';

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
const inboxOptions = computed(() => [
  { value: '', label: t('CAPTAIN.AGENT_TABS.INBOXES.SELECT_INBOX') },
  ...availableInboxes.value.map(i => ({ value: i.id, label: i.name })),
]);

const showConnect = ref(false);
const selectedInboxId = ref('');

onMounted(() => {
  store.dispatch('captainInboxes/get', { assistantId: assistantId.value });
  store.dispatch('inboxes/get');
});

async function connectInbox() {
  const inboxId = Number(selectedInboxId.value);
  if (!inboxId) return;
  await store.dispatch('captainInboxes/create', {
    assistantId: assistantId.value,
    inboxId,
  });
  selectedInboxId.value = '';
  showConnect.value = false;
  store.dispatch('captainInboxes/get', { assistantId: assistantId.value });
}

async function disconnectInbox(inboxId) {
  await store.dispatch('captainInboxes/delete', {
    assistantId: assistantId.value,
    inboxId,
  });
}

const CHANNEL_STYLE = {
  'Channel::WebWidget': { icon: 'i-lucide-globe', tint: '#30b0c7' },
  'Channel::Api': { icon: 'i-lucide-zap', tint: '#ff9500' },
  'Channel::WhatsApp': { icon: 'i-lucide-smartphone', tint: '#1faa59' },
  'Channel::Email': { icon: 'i-lucide-mail', tint: '#0a84ff' },
  'Channel::Telegram': { icon: 'i-lucide-send', tint: '#30b0c7' },
  'Channel::FacebookPage': { icon: 'i-lucide-user', tint: '#5e5ce6' },
};
const channelStyle = type =>
  CHANNEL_STYLE[type] || { icon: 'i-lucide-inbox', tint: '#8e8e93' };

const UNLINK_ACTIONS = computed(() => [
  {
    value: 'disconnect',
    label: t('CAPTAIN.AGENT_TABS.INBOXES.CONNECT_BTN'),
    icon: 'i-lucide-unlink',
    danger: true,
  },
]);
const onInboxAction = (action, inbox) => {
  if (action === 'disconnect') disconnectInbox(inbox.id);
};
</script>

<template>
  <div class="px-6 pt-4 pb-10 mx-auto max-w-3xl">
    <div class="flex justify-between items-center mb-4">
      <h3 class="text-[15px] font-bold text-n-slate-12">
        {{ t('AGENT_DETAIL.TABS.INBOXES') }}
      </h3>
      <AiButton @click="showConnect = !showConnect">
        <span class="i-lucide-plus size-4" />
        {{ t('CAPTAIN.AGENT_TABS.INBOXES.CONNECT') }}
      </AiButton>
    </div>

    <AiCard v-if="showConnect" class="mb-4">
      <div class="flex gap-2 items-center">
        <div class="flex-1">
          <AiSelect v-model="selectedInboxId" :options="inboxOptions" />
        </div>
        <AiButton :disabled="!selectedInboxId" @click="connectInbox">
          {{ t('CAPTAIN.AGENT_TABS.INBOXES.CONNECT_BTN') }}
        </AiButton>
      </div>
    </AiCard>

    <div
      v-if="isFetching"
      class="flex gap-2 items-center text-sm text-n-slate-10"
    >
      <span class="i-lucide-loader-2 size-3.5 animate-spin" />
      {{ t('CAPTAIN.AGENT_TABS.INBOXES.LOADING') }}
    </div>
    <AiEmptyState
      v-else-if="!connectedInboxes.length"
      icon="i-lucide-inbox"
      :title="t('CAPTAIN.AGENT_TABS.INBOXES.NO_INBOXES')"
    />
    <div v-else class="space-y-2.5">
      <div
        v-for="inbox in connectedInboxes"
        :key="inbox.id"
        class="flex gap-3 items-center p-3.5 rounded-2xl border shadow-sm transition-shadow border-n-weak bg-n-solid-1 hover:shadow-md"
      >
        <span
          class="grid flex-none text-white rounded-xl place-items-center size-9"
          :style="{ background: channelStyle(inbox.channel_type).tint }"
        >
          <span :class="channelStyle(inbox.channel_type).icon" class="size-4" />
        </span>
        <div class="flex-1 min-w-0">
          <p class="text-[14px] font-bold truncate text-n-slate-12">
            {{ inbox.name }}
          </p>
          <p class="text-[12px] text-n-slate-10">{{ inbox.channel_type }}</p>
        </div>
        <AiDropdown
          :items="UNLINK_ACTIONS"
          @select="onInboxAction($event, inbox)"
        />
      </div>
    </div>
  </div>
</template>
