<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['scheduleMessage', 'removeItem', 'manageScheduled']);

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const isLoadingMore = ref(false);

const stages = computed(() =>
  store.getters['kanban/getFunnelStages'](props.funnelId)
);
const viewFilters = computed(() => store.getters['kanban/getViewFilters']);
const viewBootstrap = computed(() => store.getters['kanban/getViewBootstrap']);
const uiFlags = computed(() => store.getters['kanban/getUIFlags']);
const scheduledMessages = computed(
  () => store.getters['kanban/getScheduledMessages']
);

const getConversationById = computed(
  () => store.getters['conversations/getConversationById']
);

const getConversationLabels = computed(
  () => store.getters['conversationLabels/getConversationLabels']
);

const normalizeText = value => String(value || '').toLowerCase();

const extractAssigneeId = source => {
  if (!source) return null;

  return (
    source.assigneeId ||
    source.assignee_id ||
    source.assignee?.id ||
    source.assignee?.user?.id ||
    source.meta?.assignee?.id ||
    source.meta?.assignee_id ||
    null
  );
};

const conversationIdFromItem = item => {
  const value =
    item?.conversationId ||
    item?.conversation_id ||
    item?.conversation?.id ||
    item?.conversation?.displayId ||
    item?.conversation?.display_id;
  const normalized = Number(value);
  return Number.isNaN(normalized) ? null : normalized;
};

const conversationKeyFromItem = item => {
  const value =
    item?.conversationId ||
    item?.conversation_id ||
    item?.conversation?.id ||
    item?.conversation?.displayId ||
    item?.conversation?.display_id;

  if (value == null) return null;
  return String(value);
};

const allItems = computed(() => {
  if (!Array.isArray(stages.value)) return [];

  return stages.value.flatMap(stage => {
    const stageItems = store.getters['kanban/getFunnelItems'](
      props.funnelId,
      stage.id
    );

    return stageItems.map(item => ({
      ...item,
      stageId: Number(stage.id),
      stageName: stage.name,
      stageColor: stage.color,
      stagePosition: Number(stage.position || 0),
    }));
  });
});

const conversations = computed(() => {
  const conversationMap = {};

  allItems.value.forEach(item => {
    const conversationKey = conversationKeyFromItem(item);
    if (!conversationKey || conversationMap[conversationKey]) return;

    const itemConversation = item.conversation || {};
    const numericConversationId = conversationIdFromItem(item);
    const storeConversation =
      numericConversationId && typeof getConversationById.value === 'function'
        ? getConversationById.value(numericConversationId)
        : null;

    const mergedConversation = {
      ...(storeConversation || {}),
      ...itemConversation,
    };

    const contact =
      mergedConversation.contact ||
      storeConversation?.meta?.sender ||
      storeConversation?.contact ||
      {};

    conversationMap[conversationKey] = {
      ...mergedConversation,
      id: numericConversationId || mergedConversation.id || null,
      displayId:
        mergedConversation.displayId ||
        mergedConversation.display_id ||
        numericConversationId ||
        conversationKey,
      status: mergedConversation.status || 'open',
      assigneeId: extractAssigneeId(mergedConversation),
      contact,
      lastMessageText:
        mergedConversation?.lastMessage?.processed_message_content ||
        mergedConversation?.lastMessage?.content ||
        mergedConversation?.last_message?.processed_message_content ||
        mergedConversation?.last_message?.content ||
        '',
      lastActivityAt:
        mergedConversation.lastActivityAt ||
        mergedConversation.last_activity_at ||
        mergedConversation.updatedAt ||
        mergedConversation.updated_at ||
        null,
    };
  });

  return conversationMap;
});

const hasMoreResults = computed(
  () => (viewBootstrap.value?.listQueueStageIds || []).length > 0
);

const hasActiveFilters = computed(() => {
  const filters = viewFilters.value || {};
  return Boolean(
    normalizeText(filters.query || '').trim() ||
      (filters.stageIds || []).length ||
      (filters.labelIds || []).length ||
      filters.assigneeId ||
      (filters.status || 'all') !== 'all'
  );
});

const getConversationFromItem = item => {
  const conversationKey = conversationKeyFromItem(item);
  if (!conversationKey) return item.conversation || {};

  return conversations.value[conversationKey] || item.conversation || {};
};

const getContactName = item => {
  const conversation = getConversationFromItem(item);
  return conversation?.contact?.name || t('KANBAN.ITEMS.UNNAMED_CONTACT');
};

const getContactPhone = item => {
  const conversation = getConversationFromItem(item);
  return (
    conversation?.contact?.phoneNumber ||
    conversation?.contact?.phone_number ||
    conversation?.contact?.identifier ||
    ''
  );
};

const getContactAvatar = item => {
  const conversation = getConversationFromItem(item);
  return (
    conversation?.contact?.thumbnail ||
    conversation?.contact?.avatar_url ||
    conversation?.contact?.avatar ||
    conversation?.contact?.profile_image_url ||
    ''
  );
};

const getConversationId = item => {
  const conversation = getConversationFromItem(item);

  return (
    conversation?.displayId ||
    conversation?.display_id ||
    conversation?.id ||
    item?.conversation?.displayId ||
    item?.conversation?.display_id ||
    item?.conversation?.id ||
    item?.conversationId ||
    item?.conversation_id ||
    null
  );
};

const getConversationStatus = item => {
  const conversation = getConversationFromItem(item);
  return conversation?.status || 'open';
};

const getLastMessage = item => {
  const conversation = getConversationFromItem(item);
  return conversation?.lastMessageText || '';
};

const getLastActivity = item => {
  const conversation = getConversationFromItem(item);
  return conversation?.lastActivityAt || null;
};

const getConversationLabelItems = item => {
  const conversationId = conversationIdFromItem(item);
  if (!conversationId || typeof getConversationLabels.value !== 'function') {
    return [];
  }

  const labels = getConversationLabels.value(conversationId);
  return Array.isArray(labels) ? labels : [];
};

const getPendingScheduledMessagesForConversation = item => {
  const conversationId = conversationIdFromItem(item);
  if (!conversationId) return [];

  return scheduledMessages.value
    .filter(message => {
      return (
        message.status === 'pending' &&
        Number(message.conversationId || message.conversation_id) ===
          Number(conversationId)
      );
    })
    .sort((a, b) => new Date(a.scheduledAt) - new Date(b.scheduledAt));
};

const getPendingScheduledCount = item =>
  getPendingScheduledMessagesForConversation(item).length;

const getNextPendingScheduledAt = item => {
  const [nextMessage] = getPendingScheduledMessagesForConversation(item);
  return nextMessage?.scheduledAt || null;
};

const statusLabel = status => {
  const labels = {
    open: t('KANBAN.STATUS.OPEN'),
    pending: t('KANBAN.STATUS.PENDING'),
    resolved: t('KANBAN.STATUS.RESOLVED'),
    snoozed: t('KANBAN.STATUS.SNOOZED'),
  };

  return labels[status] || t('KANBAN.STATUS.OPEN');
};

const statusBadgeClass = status => {
  if (status === 'pending') return 'bg-n-amber-4 text-n-amber-11';
  if (status === 'resolved') return 'bg-n-slate-4 text-n-slate-11';
  if (status === 'snoozed') return 'bg-n-blue-4 text-n-blue-11';
  return 'bg-n-emerald-4 text-n-emerald-11';
};

const matchesQueryFilter = item => {
  const query = normalizeText(viewFilters.value?.query || '').trim();
  if (!query) return true;

  const conversation = getConversationFromItem(item);
  const haystack = [
    getContactName(item),
    getContactPhone(item),
    conversation?.displayId,
    conversation?.display_id,
    conversation?.lastMessageText,
    item?.stageName,
  ]
    .map(normalizeText)
    .join(' ');

  return haystack.includes(query);
};

const matchesStageFilter = item => {
  const stageIds = viewFilters.value?.stageIds || [];
  if (!stageIds.length) return true;

  return stageIds.map(Number).includes(Number(item.stageId));
};

const matchesLabelFilter = item => {
  const labelIds = viewFilters.value?.labelIds || [];
  if (!labelIds.length) return true;

  const selectedIds = new Set(labelIds.map(Number));
  return getConversationLabelItems(item).some(label =>
    selectedIds.has(Number(label.id))
  );
};

const matchesAssigneeFilter = item => {
  const selectedAssigneeId = Number(viewFilters.value?.assigneeId || 0);
  if (!selectedAssigneeId) return true;

  const conversation = getConversationFromItem(item);
  const assigneeId =
    extractAssigneeId(item?.conversation) ||
    extractAssigneeId(conversation) ||
    null;

  return Number(assigneeId) === selectedAssigneeId;
};

const matchesStatusFilter = item => {
  const selectedStatus = viewFilters.value?.status || 'all';
  if (selectedStatus === 'all') return true;
  return getConversationStatus(item) === selectedStatus;
};

const filteredItems = computed(() => {
  return allItems.value
    .filter(item => {
      return (
        matchesQueryFilter(item) &&
        matchesStageFilter(item) &&
        matchesLabelFilter(item) &&
        matchesAssigneeFilter(item) &&
        matchesStatusFilter(item)
      );
    })
    .sort((a, b) => {
      if (a.stagePosition !== b.stagePosition) {
        return a.stagePosition - b.stagePosition;
      }

      const aTime = new Date(getLastActivity(a) || 0).getTime();
      const bTime = new Date(getLastActivity(b) || 0).getTime();
      return bTime - aTime;
    });
});

const clearFilters = () => {
  store.dispatch('kanban/resetViewFilters');
};

const openConversation = item => {
  const conversationId = getConversationId(item);
  if (!conversationId) return;

  router.push({
    name: 'inbox_conversation',
    params: { conversation_id: conversationId },
  });
};

const openScheduledManager = item => {
  const conversationId = getConversationId(item);
  if (!conversationId) return;

  emit('manageScheduled', conversationId);
};

const handleRemove = async item => {
  if (!window.confirm(t('KANBAN.ITEMS.CONFIRM_REMOVE'))) return;

  try {
    await store.dispatch('kanban/deleteItem', {
      funnelId: props.funnelId,
      itemId: item.id,
    });
    emit('removeItem', item);
  } catch (_) {
    // noop
  }
};

const loadMoreResults = async () => {
  if (!hasMoreResults.value || isLoadingMore.value) return;

  isLoadingMore.value = true;
  try {
    await store.dispatch('kanban/loadMoreListQueue', {
      funnelId: props.funnelId,
      limit: 15,
    });
  } finally {
    isLoadingMore.value = false;
  }
};
</script>

<template>
  <div
    class="list-view-container flex h-full w-full flex-col overflow-hidden bg-n-background"
  >
    <div
      v-if="uiFlags.isFetching && allItems.length === 0"
      class="flex h-full items-center justify-center"
    >
      <div class="flex flex-col items-center text-center">
        <Icon
          icon="i-lucide-loader-2"
          class="mb-3 size-7 animate-spin text-n-slate-10"
        />
        <p class="text-sm text-n-slate-10">
          {{ t('KANBAN.LOADING_CONVERSATIONS') }}
        </p>
      </div>
    </div>

    <div
      v-else-if="allItems.length === 0"
      class="flex h-full flex-col items-center justify-center px-6 text-center"
    >
      <Icon icon="i-lucide-inbox" class="mb-3 size-10 text-n-slate-9" />
      <h3 class="text-lg font-semibold text-n-slate-12">
        {{ t('KANBAN.ITEMS.NO_ITEMS') }}
      </h3>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ t('KANBAN.LIST.EMPTY_HELPER') }}
      </p>
    </div>

    <template v-else>
      <div
        class="flex items-center justify-between gap-3 border-b border-n-weak bg-white dark:bg-n-solid-2 px-5 py-3"
      >
        <div class="flex items-center gap-2 text-sm text-n-slate-10">
          <Icon icon="i-lucide-list-filter" class="size-4" />
          <span>
            {{
              t('KANBAN.LIST.RESULT_COUNT', {
                shown: filteredItems.length,
                total: allItems.length,
              })
            }}
          </span>
        </div>

        <Button
          v-if="hasActiveFilters"
          size="sm"
          variant="ghost"
          icon="i-lucide-filter-x"
          @click="clearFilters"
        >
          <span class="ml-2">{{ t('KANBAN.FILTERS.CLEAR') }}</span>
        </Button>
      </div>

      <div
        v-if="filteredItems.length === 0"
        class="flex h-full flex-col items-center justify-center px-6 text-center"
      >
        <Icon icon="i-lucide-search-x" class="mb-3 size-10 text-n-slate-9" />
        <h3 class="text-lg font-semibold text-n-slate-12">
          {{ t('KANBAN.LIST.NO_RESULTS') }}
        </h3>
        <p class="mt-1 text-sm text-n-slate-10">
          {{ t('KANBAN.LIST.NO_RESULTS_HELPER') }}
        </p>
      </div>

      <div v-else class="flex-1 overflow-y-auto">
        <div class="hidden min-w-[980px] lg:block">
          <div
            class="grid grid-cols-[2.1fr_1.1fr_0.9fr_1.6fr_1fr_0.8fr] items-center gap-3 border-b border-n-weak bg-white dark:bg-n-solid-2 px-5 py-3 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            <span>{{ t('KANBAN.LIST.CONTACT') }}</span>
            <span>{{ t('KANBAN.LIST.STAGE') }}</span>
            <span>{{ t('KANBAN.LIST.STATUS') }}</span>
            <span>{{ t('KANBAN.LIST.LAST_MESSAGE') }}</span>
            <span>{{ t('KANBAN.LIST.SCHEDULED_PENDING') }}</span>
            <span class="text-right">{{ t('KANBAN.LIST.ACTIONS') }}</span>
          </div>

          <div class="divide-y divide-n-weak">
            <div
              v-for="item in filteredItems"
              :key="item.id"
              class="grid grid-cols-[2.1fr_1.1fr_0.9fr_1.6fr_1fr_0.8fr] items-center gap-3 px-5 py-3 hover:bg-n-slate-3/50 transition-colors"
            >
              <button
                type="button"
                class="flex min-w-0 items-center gap-3 text-left"
                @click="openConversation(item)"
              >
                <Avatar
                  :name="getContactName(item)"
                  :src="getContactAvatar(item)"
                  :size="38"
                  rounded-full
                />
                <div class="min-w-0">
                  <p class="truncate text-sm font-semibold text-n-slate-12">
                    {{ getContactName(item) }}
                  </p>
                  <p
                    v-if="getContactPhone(item)"
                    class="truncate text-xs font-mono text-n-slate-10"
                  >
                    {{ getContactPhone(item) }}
                  </p>
                </div>
              </button>

              <div class="min-w-0">
                <span
                  class="inline-flex items-center gap-2 rounded-full px-2.5 py-1 text-xs font-semibold text-white"
                  :style="{ backgroundColor: item.stageColor || '#94a3b8' }"
                >
                  <span class="size-1.5 rounded-full bg-white/60" />
                  <span class="truncate">{{ item.stageName }}</span>
                </span>
              </div>

              <div>
                <span
                  class="inline-flex rounded-full px-2.5 py-1 text-xs font-semibold"
                  :class="statusBadgeClass(getConversationStatus(item))"
                >
                  {{ statusLabel(getConversationStatus(item)) }}
                </span>
              </div>

              <div class="min-w-0">
                <p class="line-clamp-2 text-sm text-n-slate-11">
                  {{ getLastMessage(item) || t('KANBAN.ITEMS.NO_MESSAGE') }}
                </p>
              </div>

              <div>
                <span
                  v-if="getPendingScheduledCount(item) > 0"
                  class="inline-flex items-center gap-1.5 rounded-full bg-n-teal-3 px-2.5 py-1 text-xs font-semibold text-n-teal-11"
                >
                  <Icon icon="i-lucide-clock-3" class="size-3.5" />
                  {{
                    t('KANBAN.SCHEDULED_MESSAGES.CONVERSATION_PENDING', {
                      count: getPendingScheduledCount(item),
                    })
                  }}
                </span>
                <p
                  v-if="getNextPendingScheduledAt(item)"
                  class="mt-1 text-[11px] text-n-slate-10"
                >
                  {{
                    format(
                      new Date(getNextPendingScheduledAt(item)),
                      'dd/MM HH:mm'
                    )
                  }}
                </p>
                <span v-else class="text-xs text-n-slate-9">{{
                  t('KANBAN.LIST.NONE')
                }}</span>
              </div>

              <div class="flex items-center justify-end gap-1" @click.stop>
                <Button
                  size="xs"
                  variant="ghost"
                  icon="i-lucide-clock"
                  :title="t('KANBAN.SCHEDULED_MESSAGES.CREATE')"
                  class="!h-8 !w-8 !p-0"
                  @click="
                    emit('scheduleMessage', getConversationFromItem(item))
                  "
                />
                <Button
                  size="xs"
                  variant="ghost"
                  icon="i-lucide-list-checks"
                  :title="t('KANBAN.SCHEDULED_MESSAGES.MANAGE')"
                  class="!h-8 !w-8 !p-0"
                  @click="openScheduledManager(item)"
                />
                <Button
                  size="xs"
                  variant="ghost"
                  icon="i-lucide-trash"
                  :title="t('KANBAN.ITEMS.REMOVE')"
                  class="!h-8 !w-8 !p-0 text-ruby-10"
                  @click="handleRemove(item)"
                />
              </div>
            </div>
          </div>
        </div>

        <div class="space-y-3 p-4 lg:hidden">
          <div
            v-for="item in filteredItems"
            :key="item.id"
            class="rounded-xl border border-n-weak bg-white dark:bg-n-solid-2 p-3 hover:shadow-sm transition-shadow"
          >
            <div class="flex items-start justify-between gap-3">
              <button
                type="button"
                class="flex min-w-0 items-center gap-3 text-left"
                @click="openConversation(item)"
              >
                <Avatar
                  :name="getContactName(item)"
                  :src="getContactAvatar(item)"
                  :size="36"
                  rounded-full
                />
                <div class="min-w-0">
                  <p class="truncate text-sm font-semibold text-n-slate-12">
                    {{ getContactName(item) }}
                  </p>
                  <p
                    v-if="getContactPhone(item)"
                    class="truncate text-xs font-mono text-n-slate-10"
                  >
                    {{ getContactPhone(item) }}
                  </p>
                </div>
              </button>

              <span
                class="inline-flex rounded-full px-2 py-0.5 text-[11px] font-semibold"
                :class="statusBadgeClass(getConversationStatus(item))"
              >
                {{ statusLabel(getConversationStatus(item)) }}
              </span>
            </div>

            <div class="mt-3 flex items-center gap-2">
              <span
                class="inline-flex items-center gap-2 rounded-full px-2.5 py-1 text-xs font-semibold text-white"
                :style="{ backgroundColor: item.stageColor || '#94a3b8' }"
              >
                <span class="size-1.5 rounded-full bg-white/60" />
                {{ item.stageName }}
              </span>
              <span
                v-if="getPendingScheduledCount(item) > 0"
                class="inline-flex items-center gap-1 rounded-full bg-n-teal-3 px-2 py-1 text-[11px] font-semibold text-n-teal-11"
              >
                <Icon icon="i-lucide-clock-3" class="size-3" />
                {{ getPendingScheduledCount(item) }}
              </span>
            </div>

            <p class="mt-3 line-clamp-2 text-sm text-n-slate-11">
              {{ getLastMessage(item) || t('KANBAN.ITEMS.NO_MESSAGE') }}
            </p>

            <div class="mt-3 flex items-center justify-end gap-1" @click.stop>
              <Button
                size="xs"
                variant="ghost"
                icon="i-lucide-clock"
                class="!h-8 !w-8 !p-0"
                @click="emit('scheduleMessage', getConversationFromItem(item))"
              />
              <Button
                size="xs"
                variant="ghost"
                icon="i-lucide-list-checks"
                class="!h-8 !w-8 !p-0"
                @click="openScheduledManager(item)"
              />
              <Button
                size="xs"
                variant="ghost"
                icon="i-lucide-trash"
                class="!h-8 !w-8 !p-0 text-ruby-10"
                @click="handleRemove(item)"
              />
            </div>
          </div>
        </div>

        <div
          class="border-t border-n-weak bg-white dark:bg-n-solid-2 px-4 py-3"
        >
          <Button
            v-if="hasMoreResults"
            variant="ghost"
            class="w-full"
            :is-loading="isLoadingMore"
            @click="loadMoreResults"
          >
            {{ t('KANBAN.LIST.LOAD_MORE_RESULTS') }}
          </Button>

          <p v-else class="text-center text-xs text-n-slate-10">
            {{ t('KANBAN.LIST.ALL_RESULTS_LOADED') }}
          </p>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.list-view-container {
  min-height: 0;
}
</style>
