<script setup>
import { ref, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import SearchAPI from 'dashboard/api/search';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  funnelId: {
    type: Number,
    required: true,
  },
  stage: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['close', 'added']);

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const searchQuery = ref('');
const results = ref([]);
const isSearching = ref(false);
const isAdding = ref(false);

const resolveContact = conversation =>
  conversation?.meta?.sender ||
  conversation?.contact ||
  conversation?.sender ||
  {};

const lastMessageText = conversation => {
  const message =
    conversation?.last_non_activity_message ||
    conversation?.last_message ||
    conversation?.meta?.last_non_activity_message;
  return message?.content || '';
};

const runSearch = debounce(async query => {
  const term = (query || '').trim();
  if (term.length < 2) {
    results.value = [];
    isSearching.value = false;
    return;
  }
  isSearching.value = true;
  try {
    const { data } = await SearchAPI.conversations({ q: term });
    results.value = data?.payload?.conversations || data?.payload || [];
  } catch (_) {
    results.value = [];
  } finally {
    isSearching.value = false;
  }
}, 350);

watch(searchQuery, query => runSearch(query));

watch(
  () => props.show,
  newShow => {
    if (newShow) {
      searchQuery.value = '';
      results.value = [];
      nextTick(() => {
        setTimeout(() => {
          dialogRef.value?.open?.();
        }, 10);
      });
    } else {
      dialogRef.value?.close?.();
    }
  },
  { immediate: true }
);

const close = () => emit('close');

const addConversation = async conversation => {
  const conversationId = conversation?.id;
  const stageId = props.stage?.id;
  if (!conversationId || !stageId || isAdding.value) return;

  isAdding.value = true;
  try {
    await store.dispatch('kanban/createItem', {
      funnelId: props.funnelId,
      data: {
        conversation_id: conversationId,
        funnel_stage_id: stageId,
      },
    });
    useAlert(t('KANBAN.ITEMS.ADD_SUCCESS'));
    emit('added', { conversationId, stageId });
    close();
  } catch (error) {
    const status = error?.response?.status;
    // Unique index (conversation_id, funnel_id) → already in this funnel.
    const message =
      status === 422
        ? t('KANBAN.ITEMS.ADD_DUPLICATE')
        : t('KANBAN.ITEMS.ADD_ERROR');
    useAlert(message);
  } finally {
    isAdding.value = false;
  }
};
</script>

<template>
  <Dialog
    v-if="show && stage"
    ref="dialogRef"
    :title="t('KANBAN.ITEMS.ADD')"
    :description="stage.name"
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="md"
    @close="close"
  >
    <div class="space-y-3">
      <div class="relative">
        <Icon
          icon="i-lucide-search"
          class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
        />
        <input
          v-model="searchQuery"
          type="search"
          autofocus
          :placeholder="t('KANBAN.ITEMS.ADD_SEARCH_PLACEHOLDER')"
          class="h-11 w-full rounded-xl border border-n-weak bg-n-solid-1 pl-10 pr-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-teal-9"
        />
      </div>

      <div class="max-h-80 overflow-y-auto">
        <div
          v-if="isSearching"
          class="flex items-center justify-center gap-2 py-8 text-sm text-n-slate-10"
        >
          <Icon icon="i-lucide-loader-2" class="size-4 animate-spin" />
          {{ t('KANBAN.LOADING') }}
        </div>

        <div
          v-else-if="searchQuery.trim().length >= 2 && !results.length"
          class="py-8 text-center text-sm text-n-slate-10"
        >
          {{ t('KANBAN.ITEMS.ADD_NO_RESULTS') }}
        </div>

        <ul v-else class="flex flex-col gap-1">
          <li v-for="conversation in results" :key="conversation.id">
            <button
              class="flex w-full items-center gap-3 rounded-xl border border-transparent p-2 text-left transition hover:border-n-weak hover:bg-n-alpha-1 disabled:opacity-50"
              :disabled="isAdding"
              @click="addConversation(conversation)"
            >
              <Avatar
                :name="resolveContact(conversation).name || ''"
                :src="
                  resolveContact(conversation).thumbnail ||
                  resolveContact(conversation).avatar_url
                "
                :size="32"
                rounded-full
              />
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-medium text-n-slate-12">
                  {{
                    resolveContact(conversation).name ||
                    t('KANBAN.ITEMS.UNNAMED_CONTACT')
                  }}
                  <span class="text-n-slate-9">#{{ conversation.id }}</span>
                </p>
                <p
                  v-if="lastMessageText(conversation)"
                  class="truncate text-xs text-n-slate-10"
                >
                  {{ lastMessageText(conversation) }}
                </p>
              </div>
              <Icon
                icon="i-lucide-plus"
                class="size-4 shrink-0 text-n-slate-10"
              />
            </button>
          </li>
        </ul>

        <div
          v-if="!searchQuery.trim()"
          class="py-8 text-center text-xs text-n-slate-9"
        >
          {{ t('KANBAN.ITEMS.ADD_HINT') }}
        </div>
      </div>
    </div>
  </Dialog>
</template>
