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
const noteRef = ref(null);
const isLoading = ref(false);

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
// Erro aparece dentro da janela (o aviso flutuante nasce atrás do <dialog>).
const shareError = ref(false);

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
  shareError.value = false;
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
    shareError.value = true;
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
      shareError.value = false;
      isLoading.value = !store.getters['internalChat/getAgents'].length;
      Promise.allSettled([
        store.dispatch('internalChat/fetchChannels'),
        store.dispatch('internalChat/fetchAgents'),
      ]).then(() => {
        isLoading.value = false;
      });
      nextTick(() => {
        setTimeout(() => {
          dialogRef.value?.open?.();
          nextTick(() => noteRef.value?.focus());
        }, 10);
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
    show-close-button
    full-height
    width="md"
    @close="close"
  >
    <div class="flex flex-col flex-1 min-h-0 gap-4">
      <p class="mb-0 text-sm text-n-slate-11">
        {{
          t('INTERNAL_CHAT.SHARE.SUBTITLE', {
            id: displayId,
            name: contactName,
          })
        }}
      </p>

      <textarea
        ref="noteRef"
        v-model="note"
        rows="2"
        :aria-label="t('INTERNAL_CHAT.SHARE.NOTE_PLACEHOLDER')"
        class="reset-base flex-shrink-0 w-full h-auto !mb-0 px-3 py-2 text-sm !bg-n-alpha-1 !border !border-solid !border-n-weak rounded-lg text-n-slate-12 !outline-none focus:!border-n-teal-9 resize-none"
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

      <div class="flex-1 min-h-[8rem] overflow-y-auto -mx-1 px-1 space-y-3">
        <p
          v-if="isLoading"
          class="flex items-center justify-center gap-2 py-4 mb-0 text-sm text-n-slate-11"
        >
          <span class="i-lucide-loader-circle animate-spin" />
          {{ t('INTERNAL_CHAT.LOADING') }}
        </p>
        <div v-if="channels.length">
          <p class="mb-1 text-sm font-medium text-n-slate-11">
            {{ t('INTERNAL_CHAT.SHARE.CHANNELS') }}
          </p>
          <button
            v-for="channel in channels"
            :key="`c-${channel.id}`"
            type="button"
            class="flex items-center gap-2.5 w-full px-2 py-2 rounded-lg text-sm text-n-slate-12"
            :class="
              isSelected('channel', channel.id)
                ? 'bg-n-brand/10 ring-1 ring-n-brand'
                : 'hover:bg-n-alpha-1'
            "
            @click="pick('channel', channel.id)"
          >
            <Avatar
              :name="channel.title"
              icon-name="i-lucide-users"
              :size="26"
              rounded-full
            />
            <span class="truncate" :title="channel.title">
              {{ channel.title }}
            </span>
          </button>
        </div>

        <div v-if="agents.length">
          <p class="mb-1 text-sm font-medium text-n-slate-11">
            {{ t('INTERNAL_CHAT.SHARE.PEOPLE') }}
          </p>
          <button
            v-for="agent in agents"
            :key="`a-${agent.id}`"
            type="button"
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
            <span class="truncate" :title="agent.name">{{ agent.name }}</span>
          </button>
        </div>
        <p
          v-if="!isLoading && !channels.length && !agents.length"
          class="mb-0 py-4 text-sm text-center text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.SHARE.NO_MATCH') }}
        </p>
      </div>
    </div>

    <template #footer>
      <div class="flex items-center justify-end w-full gap-3 shrink-0">
        <span
          v-if="shareError"
          role="alert"
          class="flex-1 min-w-0 text-xs text-n-ruby-11"
        >
          {{ t('INTERNAL_CHAT.SHARE.ERROR') }}
        </span>
        <span
          v-else-if="!selected"
          class="flex-1 min-w-0 text-xs text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.SHARE.PICK_FIRST') }}
        </span>
        <Button
          type="button"
          variant="faded"
          color="slate"
          @click="dialogRef?.close()"
        >
          {{ t('INTERNAL_CHAT.CANCEL') }}
        </Button>
        <Button
          type="button"
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
