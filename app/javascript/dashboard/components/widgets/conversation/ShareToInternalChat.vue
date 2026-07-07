<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  conversation: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();
const dialogRef = ref(null);

const channels = computed(() => store.getters['internalChat/getChannels']);
const agents = computed(() => store.getters['internalChat/getAgents']);
const note = ref('');
const selected = ref(null); // { type: 'channel' | 'agent', id }
const isSending = ref(false);

const displayId = computed(
  () => props.conversation?.display_id ?? props.conversation?.id
);
const contactName = computed(
  () => props.conversation?.meta?.sender?.name || ''
);

const isSelected = (type, id) =>
  selected.value?.type === type && selected.value?.id === id;
const pick = (type, id) => {
  selected.value = { type, id };
};

const close = () => emit('close');

const share = async () => {
  if (!selected.value || !displayId.value) return;
  isSending.value = true;
  try {
    await store.dispatch('internalChat/shareConversation', {
      channelId: selected.value.type === 'channel' ? selected.value.id : null,
      userId: selected.value.type === 'agent' ? selected.value.id : null,
      conversationDisplayId: displayId.value,
      note: note.value.trim(),
    });
    useAlert(t('INTERNAL_CHAT.SHARE.DONE'));
    close();
  } catch (e) {
    useAlert(t('INTERNAL_CHAT.SHARE.ERROR'));
  } finally {
    isSending.value = false;
  }
};

watch(
  () => props.show,
  show => {
    if (show) {
      note.value = '';
      selected.value = null;
      store.dispatch('internalChat/fetchChannels');
      store.dispatch('internalChat/fetchAgents');
      nextTick(() => {
        setTimeout(() => dialogRef.value?.open?.(), 10);
      });
    } else {
      dialogRef.value?.close?.();
    }
  },
  { immediate: true }
);
</script>

<template>
  <Dialog
    v-if="show"
    ref="dialogRef"
    :title="t('INTERNAL_CHAT.SHARE.TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="md"
    @close="close"
  >
    <div class="space-y-4">
      <p class="text-sm text-n-slate-11">
        {{
          t('INTERNAL_CHAT.SHARE.SUBTITLE', {
            id: displayId,
            name: contactName,
          })
        }}
      </p>

      <textarea
        v-model="note"
        rows="2"
        class="w-full px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12 focus:outline-none focus:border-n-brand resize-none"
        :placeholder="t('INTERNAL_CHAT.SHARE.NOTE_PLACEHOLDER')"
      />

      <div class="max-h-72 overflow-y-auto -mx-1 px-1 space-y-3">
        <div v-if="channels.length">
          <p class="text-xs font-medium uppercase text-n-slate-10 mb-1">
            {{ t('INTERNAL_CHAT.SHARE.CHANNELS') }}
          </p>
          <button
            v-for="channel in channels"
            :key="`c-${channel.id}`"
            class="flex items-center gap-2.5 w-full px-2 py-2 rounded-lg text-sm text-n-slate-12"
            :class="
              isSelected('channel', channel.id)
                ? 'bg-n-brand/10 ring-1 ring-n-brand'
                : 'hover:bg-n-alpha-1'
            "
            @click="pick('channel', channel.id)"
          >
            <Avatar :name="channel.title" :size="26" rounded-full />
            <span class="truncate">{{ channel.title }}</span>
          </button>
        </div>

        <div>
          <p class="text-xs font-medium uppercase text-n-slate-10 mb-1">
            {{ t('INTERNAL_CHAT.SHARE.PEOPLE') }}
          </p>
          <button
            v-for="agent in agents"
            :key="`a-${agent.id}`"
            class="flex items-center gap-2.5 w-full px-2 py-2 rounded-lg text-sm text-n-slate-12"
            :class="
              isSelected('agent', agent.id)
                ? 'bg-n-brand/10 ring-1 ring-n-brand'
                : 'hover:bg-n-alpha-1'
            "
            @click="pick('agent', agent.id)"
          >
            <Avatar
              :src="agent.avatar_url"
              :name="agent.name"
              :size="26"
              rounded-full
            />
            <span class="truncate">{{ agent.name }}</span>
          </button>
        </div>
      </div>
    </div>

    <template #footer>
      <div class="flex justify-end gap-3">
        <Button variant="ghost" @click="close">
          {{ t('INTERNAL_CHAT.CANCEL') }}
        </Button>
        <Button
          color="blue"
          :is-loading="isSending"
          :disabled="!selected"
          @click="share"
        >
          {{ t('INTERNAL_CHAT.SHARE.CONFIRM') }}
        </Button>
      </div>
    </template>
  </Dialog>
</template>
