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

// Grupos e times aqui; conversa de 1 a 1 é por "Pessoas" (antes a mesma pessoa
// aparecia nas duas listas). A busca filtra as duas.
const query = ref('');
const matches = name =>
  (name || '').toLowerCase().includes(query.value.trim().toLowerCase());
const channels = computed(() =>
  store.getters['internalChat/getChannels'].filter(
    c => c.channel_type !== 'direct' && matches(c.title)
  )
);
const agents = computed(() =>
  store.getters['internalChat/getAgents'].filter(a => matches(a.name))
);
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
      // O backend exige texto: sem comentário vai uma frase padrão (o card com
      // o link da conversa aparece junto no balão).
      note:
        note.value.trim() ||
        t('INTERNAL_CHAT.SHARE.DEFAULT_NOTE', { id: displayId.value }),
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
      query.value = '';
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

      <div class="relative">
        <span
          class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-3 top-1/2 text-n-slate-10"
        />
        <input
          v-model="query"
          type="text"
          :placeholder="t('INTERNAL_CHAT.SHARE.SEARCH')"
          :aria-label="t('INTERNAL_CHAT.SHARE.SEARCH')"
          class="reset-base w-full h-9 pl-9 pr-3 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12 focus:outline-none focus:border-n-brand"
        />
      </div>

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

        <div v-if="agents.length">
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
        <p
          v-if="!channels.length && !agents.length"
          class="py-4 text-sm text-center text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.SHARE.NO_MATCH') }}
        </p>
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
