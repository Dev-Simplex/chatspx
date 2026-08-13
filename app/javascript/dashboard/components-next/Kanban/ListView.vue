<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useStageColor } from './composables/useStageColor';

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
const { accent, contrastText } = useStageColor();

const stageBadgeStyle = color => {
  const bg = accent(color);
  return { backgroundColor: bg, color: contrastText(bg) };
};

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
  return 'bg-n-teal-4 text-n-teal-11';
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

const matchesPriorityFilter = item => {
  const priorities = viewFilters.value?.priority || [];
  if (!priorities.length) return true;
  const conversation = getConversationFromItem(item);
  const priority =
    conversation?.priority || item?.conversation?.priority || null;
  if (priority == null) return priorities.includes('none');
  return priorities.includes(priority);
};

const filteredItems = computed(() => {
  return allItems.value
    .filter(item => {
      return (
        matchesQueryFilter(item) &&
        matchesStageFilter(item) &&
        matchesLabelFilter(item) &&
        matchesAssigneeFilter(item) &&
        matchesStatusFilter(item) &&
        matchesPriorityFilter(item)
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

// ── Bulk actions (Fase 3) — select rows, then reassign/tag/archive/move ─
const agentsList = computed(() => store.getters['agents/getAgents'] || []);
const selectMode = ref(false);
const selectedIds = ref([]);
const bulkBusy = ref(false);
const tagDraft = ref('');

const selectableIds = computed(() =>
  filteredItems.value.map(conversationIdFromItem).filter(Boolean)
);
const selectedCount = computed(() => selectedIds.value.length);
const allSelected = computed(
  () =>
    selectableIds.value.length > 0 &&
    selectableIds.value.every(id => selectedIds.value.includes(id))
);

const isSelected = item =>
  selectedIds.value.includes(conversationIdFromItem(item));
const toggleSelect = item => {
  const id = conversationIdFromItem(item);
  if (!id) return;
  selectedIds.value = selectedIds.value.includes(id)
    ? selectedIds.value.filter(x => x !== id)
    : [...selectedIds.value, id];
};
const toggleSelectAll = () => {
  selectedIds.value = allSelected.value ? [] : [...selectableIds.value];
};
const clearSelection = () => {
  selectedIds.value = [];
};
const toggleSelectMode = () => {
  selectMode.value = !selectMode.value;
  if (!selectMode.value) clearSelection();
};

const runBulk = async payload => {
  if (!selectedCount.value || bulkBusy.value) return;
  bulkBusy.value = true;
  try {
    const result = await store.dispatch('kanban/bulkUpdateItems', {
      funnelId: props.funnelId,
      conversationIds: [...selectedIds.value],
      ...payload,
    });
    if (result) {
      useAlert(
        t('KANBAN.BULK.RESULT', {
          processed: result.processed ?? 0,
          failed: result.failed ?? 0,
        })
      );
    }
    clearSelection();
  } catch (_) {
    useAlert(t('KANBAN.BULK.ERROR'));
  } finally {
    bulkBusy.value = false;
  }
};

const bulkReassign = event => {
  const value = event.target.value;
  event.target.value = '';
  if (value) runBulk({ operation: 'reassign', assigneeId: Number(value) });
};
const bulkTag = () => {
  const label = tagDraft.value.trim();
  if (!label) return;
  tagDraft.value = '';
  runBulk({ operation: 'tag', labels: [label] });
};
const bulkArchive = () => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('KANBAN.BULK.ARCHIVE_CONFIRM', { count: selectedCount.value })
    )
  )
    return;
  runBulk({ operation: 'archive' });
};
const bulkMove = async event => {
  const stageId = event.target.value;
  event.target.value = '';
  if (!stageId || !selectedCount.value || bulkBusy.value) return;
  bulkBusy.value = true;
  try {
    await store.dispatch('kanban/bulkMoveItems', {
      funnelId: props.funnelId,
      conversationIds: [...selectedIds.value],
      stageId: Number(stageId),
    });
    clearSelection();
  } catch (_) {
    useAlert(t('KANBAN.BULK.ERROR'));
  } finally {
    bulkBusy.value = false;
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
        class="flex items-center justify-between gap-3 border-b border-n-weak bg-n-solid-1 px-5 py-3"
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

        <div class="flex items-center gap-2">
          <Button
            v-if="hasActiveFilters"
            size="sm"
            variant="ghost"
            icon="i-lucide-filter-x"
            @click="clearFilters"
          >
            <span class="ml-2">{{ t('KANBAN.FILTERS.CLEAR') }}</span>
          </Button>
          <Button
            size="sm"
            :variant="selectMode ? 'primary' : 'ghost'"
            icon="i-lucide-check-square"
            @click="toggleSelectMode"
          >
            <span class="ml-2">
              {{
                selectMode
                  ? t('KANBAN.BULK.DONE')
                  : t('KANBAN.BULK.SELECT_MODE')
              }}
            </span>
          </Button>
        </div>
      </div>

      <!-- Bulk action bar -->
      <div
        v-if="selectMode && selectedCount"
        class="flex flex-wrap items-center gap-2 border-b border-n-weak bg-n-solid-2 px-5 py-2"
      >
        <span class="text-sm font-semibold text-n-slate-12">
          {{ t('KANBAN.BULK.SELECTED', { count: selectedCount }) }}
        </span>
        <select
          class="kanban-bulk-input"
          :disabled="bulkBusy"
          @change="bulkMove"
        >
          <option value="">{{ t('KANBAN.BULK.MOVE') }}</option>
          <option v-for="stage in stages" :key="stage.id" :value="stage.id">
            {{ stage.name }}
          </option>
        </select>
        <select
          class="kanban-bulk-input"
          :disabled="bulkBusy"
          @change="bulkReassign"
        >
          <option value="">{{ t('KANBAN.BULK.REASSIGN') }}</option>
          <option v-for="agent in agentsList" :key="agent.id" :value="agent.id">
            {{ agent.name || agent.available_name }}
          </option>
        </select>
        <span class="flex items-center gap-1">
          <input
            v-model="tagDraft"
            type="text"
            class="kanban-bulk-input w-28"
            :placeholder="t('KANBAN.BULK.TAG_PLACEHOLDER')"
            :disabled="bulkBusy"
            @keyup.enter="bulkTag"
          />
          <Button
            size="sm"
            variant="ghost"
            :disabled="bulkBusy || !tagDraft.trim()"
            @click="bulkTag"
          >
            {{ t('KANBAN.BULK.TAG') }}
          </Button>
        </span>
        <Button
          size="sm"
          variant="ghost"
          icon="i-lucide-archive"
          :disabled="bulkBusy"
          @click="bulkArchive"
        >
          <span class="ml-1">{{ t('KANBAN.BULK.ARCHIVE') }}</span>
        </Button>
        <Button
          size="sm"
          variant="ghost"
          :disabled="bulkBusy"
          @click="clearSelection"
        >
          {{ t('KANBAN.BULK.CLEAR') }}
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
            class="grid grid-cols-[2.1fr_1.1fr_0.9fr_1.6fr_1fr_0.8fr] items-center gap-3 border-b border-n-weak bg-n-solid-1 px-5 py-3 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            <span class="flex items-center gap-2">
              <input
                v-if="selectMode"
                type="checkbox"
                class="size-4 shrink-0 accent-n-brand"
                :checked="allSelected"
                @change="toggleSelectAll"
              />
              {{ t('KANBAN.LIST.CONTACT') }}
            </span>
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
              :class="{ 'bg-n-brand/5': selectMode && isSelected(item) }"
            >
              <div class="flex min-w-0 items-center gap-2">
                <input
                  v-if="selectMode"
                  type="checkbox"
                  class="size-4 shrink-0 accent-n-brand"
                  :checked="isSelected(item)"
                  @click.stop="toggleSelect(item)"
                />
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
              </div>

              <div class="min-w-0">
                <span
                  class="inline-flex items-center gap-2 rounded-full px-2.5 py-1 text-xs font-semibold"
                  :style="stageBadgeStyle(item.stageColor)"
                >
                  <span class="size-1.5 rounded-full bg-current opacity-60" />
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
                  class="!h-8 !w-8 !p-0 text-n-ruby-11"
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
            class="rounded-xl border border-n-weak bg-n-solid-1 p-3 hover:shadow-sm transition-shadow"
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
                class="inline-flex items-center gap-2 rounded-full px-2.5 py-1 text-xs font-semibold"
                :style="stageBadgeStyle(item.stageColor)"
              >
                <span class="size-1.5 rounded-full bg-current opacity-60" />
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
                class="!h-8 !w-8 !p-0 text-n-ruby-11"
                @click="handleRemove(item)"
              />
            </div>
          </div>
        </div>

        <div class="border-t border-n-weak bg-n-solid-1 px-4 py-3">
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

/* Compact controls for the bulk action bar */
.kanban-bulk-input {
  border-radius: 0.5rem;
  border: 1px solid var(--color-border-weak, rgba(0, 0, 0, 0.1));
  background-color: var(--color-background, #fff);
  padding: 0.25rem 0.5rem;
  font-size: 12px;
  line-height: 1.2;
  color: inherit;
}
.kanban-bulk-input:focus {
  outline: none;
  border-color: var(--color-woot, #1f93ff);
}
</style>
