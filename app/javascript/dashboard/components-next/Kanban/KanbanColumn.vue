<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import draggable from 'vuedraggable';
import KanbanCard from './KanbanCard.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';
import { useStageColor } from './composables/useStageColor';

const props = defineProps({
  funnelId: {
    type: Number,
    default: null,
  },
  stage: {
    type: Object,
    required: true,
  },
  items: {
    type: Array,
    default: () => [],
  },
  conversations: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits([
  'moveItem',
  'scheduleMessage',
  'removeItem',
  'editStage',
  'deleteStage',
  'addCard',
  'previewConversation',
]);

const store = useStore();
const { t } = useI18n();
const { accent, softBg, heatLevel } = useStageColor();

const showStageMenu = ref(false);
const observerLocked = ref(false);
const lastObservedAt = ref(0);

const headerGradient = computed(
  () =>
    `linear-gradient(180deg, ${softBg(props.stage?.color, 0.16)}, transparent)`
);
const stripGradient = computed(
  () =>
    `linear-gradient(90deg, ${accent(props.stage?.color)}, ${softBg(props.stage?.color, 0.45)})`
);
// Very subtle stage-tinted lane wash behind the cards.
const columnWash = computed(() => softBg(props.stage?.color, 0.05));

const cardCount = computed(() => props.items.length);

// ── WIP soft limit (per-stage, persisted in localStorage) ────────────
const WIP_KEY = 'kanban:wip';
const readWipMap = () => {
  try {
    return JSON.parse(localStorage.getItem(WIP_KEY) || '{}');
  } catch (_) {
    return {};
  }
};
const wipLimit = ref(readWipMap()[String(props.stage?.id)] ?? null);
const setWipLimit = () => {
  showStageMenu.value = false;
  const input = window.prompt(
    t('KANBAN.WIP.PROMPT'),
    wipLimit.value ? String(wipLimit.value) : ''
  );
  if (input === null) return; // cancelled
  const map = readWipMap();
  const key = String(props.stage?.id);
  const trimmed = input.trim();
  if (trimmed === '') {
    delete map[key];
    wipLimit.value = null;
  } else {
    const n = Math.max(1, Math.floor(Number(trimmed)));
    if (!Number.isFinite(n) || n < 1) return;
    map[key] = n;
    wipLimit.value = n;
  }
  try {
    localStorage.setItem(WIP_KEY, JSON.stringify(map));
  } catch (_) {
    // best effort
  }
};
const wipState = computed(() => {
  const limit = wipLimit.value;
  if (!limit) return 'none';
  if (cardCount.value > limit) return 'over';
  if (cardCount.value >= limit) return 'at';
  return 'under';
});
const wipBadgeClass = computed(() => {
  if (wipState.value === 'over') return 'bg-n-ruby-3 text-n-ruby-11';
  if (wipState.value === 'at') return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-slate-3 text-n-slate-11';
});
const wipBarPct = computed(() =>
  wipLimit.value
    ? Math.min(100, Math.round((cardCount.value / wipLimit.value) * 100))
    : 0
);
const wipBarColor = computed(() => {
  if (wipState.value === 'over') return 'rgb(var(--kanban-heat-cold))';
  if (wipState.value === 'at') return 'rgb(var(--kanban-heat-warm))';
  return accent(props.stage?.color);
});
const wipTitle = computed(() => {
  if (wipState.value === 'over')
    return t('KANBAN.WIP.OVER', {
      count: cardCount.value,
      limit: wipLimit.value,
    });
  if (wipState.value === 'at')
    return t('KANBAN.WIP.AT_LIMIT', {
      count: cardCount.value,
      limit: wipLimit.value,
    });
  return '';
});

const COLLAPSE_KEY = 'kanban:collapsed-stages';
const readCollapsedSet = () => {
  try {
    return new Set(JSON.parse(localStorage.getItem(COLLAPSE_KEY) || '[]'));
  } catch (_) {
    return new Set();
  }
};
const collapsed = ref(readCollapsedSet().has(Number(props.stage?.id)));
const toggleCollapsed = () => {
  collapsed.value = !collapsed.value;
  const set = readCollapsedSet();
  const id = Number(props.stage?.id);
  if (collapsed.value) set.add(id);
  else set.delete(id);
  try {
    localStorage.setItem(COLLAPSE_KEY, JSON.stringify([...set]));
  } catch (_) {
    // best effort
  }
};

const isResolvedStage = computed(() => {
  const type = props.stage?.automationType ?? props.stage?.automation_type;
  if (type === 'resolved') return true;
  const name = (props.stage?.name || '').toLowerCase();
  return name === 'resolvido' || name === 'resolved';
});

const stageMeta = computed(() =>
  store.getters['kanban/getStageMeta'](props.funnelId, props.stage?.id)
);

const isLoadingStage = computed(() => Boolean(stageMeta.value?.isLoading));
const isStageLoaded = computed(() => Boolean(stageMeta.value?.loaded));
const canLoadMore = computed(
  () => Boolean(stageMeta.value?.hasMore) && !isLoadingStage.value
);

const itemsWithConversations = computed(() => {
  const source = props.items || [];
  return source.map(item => {
    const conversationKey = String(
      item.conversation?.displayId ||
        item.conversation?.display_id ||
        item.conversation?.id ||
        item.conversationId ||
        item.conversation_id ||
        ''
    );

    return {
      ...item,
      conversation: props.conversations[conversationKey] ||
        item.conversation || {
          id: conversationKey,
          displayId: conversationKey,
          status: 'open',
        },
    };
  });
});

const pendingScheduledTotal = computed(() => {
  const getter = store.getters['kanban/getScheduledMessagesByConversation'];
  if (typeof getter !== 'function') return 0;
  return itemsWithConversations.value.reduce((sum, item) => {
    const conversationId =
      item.conversation?.id ||
      item.conversation?.displayId ||
      item.conversation?.display_id;
    const messages = conversationId ? getter(conversationId) : [];
    if (!Array.isArray(messages)) return sum;
    return (
      sum +
      messages.filter(message => (message?.status || 'pending') === 'pending')
        .length
    );
  }, 0);
});

// ── Column summary (aggregations per lane) ───────────────────────────
const unassignedCount = computed(
  () =>
    itemsWithConversations.value.filter(item => {
      const c = item.conversation || {};
      return !(c.assigneeId || c.assignee_id || c.meta?.assignee?.id);
    }).length
);
const coldCount = computed(
  () =>
    itemsWithConversations.value.filter(item => {
      const c = item.conversation || {};
      const lastActivity =
        c.lastActivityAt ||
        c.last_activity_at ||
        c.lastMessage?.created_at ||
        c.last_message?.created_at;
      return heatLevel(lastActivity) === 'cold';
    }).length
);

const handleEditStage = () => {
  showStageMenu.value = false;
  emit('editStage', props.stage);
};

const handleDeleteStage = () => {
  showStageMenu.value = false;
  emit('deleteStage', props.stage);
};

const resolveDropPayload = evt => {
  const addedMeta = evt?.added;
  if (!addedMeta?.element?.id) return null;

  return {
    item: addedMeta.element,
    newIndex: addedMeta.newIndex ?? evt?.newIndex ?? null,
    oldIndex: addedMeta.oldIndex ?? evt?.oldIndex ?? null,
  };
};

const handleDropChange = evt => {
  const payload = resolveDropPayload(evt);
  if (!payload) return;

  emit('moveItem', {
    ...payload,
    stageId: Number(props.stage?.id),
  });
};

const ensureStageLoaded = async () => {
  const funnelId = props.funnelId != null ? Number(props.funnelId) : null;
  const stageId = props.stage?.id != null ? Number(props.stage.id) : null;

  if (!funnelId || !stageId || isLoadingStage.value || isStageLoaded.value) {
    return;
  }

  await store.dispatch('kanban/fetchFunnelItemsPage', {
    funnelId,
    stageId,
    limit: 30,
    append: false,
  });
};

const loadMore = async () => {
  const funnelId = props.funnelId != null ? Number(props.funnelId) : null;
  const stageId = props.stage?.id != null ? Number(props.stage.id) : null;
  if (!funnelId || !stageId || isLoadingStage.value) return;

  if (!isStageLoaded.value) {
    await ensureStageLoaded();
    return;
  }

  if (!canLoadMore.value) return;

  await store.dispatch('kanban/loadNextStagePage', {
    funnelId,
    stageId,
    limit: stageMeta.value?.limit || 30,
  });
};

const handleColumnObserved = async () => {
  const now = Date.now();
  if (observerLocked.value || now - lastObservedAt.value < 500) return;

  observerLocked.value = true;
  lastObservedAt.value = now;

  try {
    if (!isStageLoaded.value) {
      await ensureStageLoaded();
      return;
    }

    if (canLoadMore.value) {
      await loadMore();
    }
  } finally {
    window.setTimeout(() => {
      observerLocked.value = false;
    }, 250);
  }
};
</script>

<template>
  <div
    class="kanban-column relative flex h-full flex-shrink-0 flex-col overflow-hidden rounded-xl bg-n-slate-2/50 dark:bg-n-solid-2"
    :class="collapsed ? 'kanban-column--collapsed' : 'kanban-column--expanded'"
    :style="{ '--col-wash': columnWash }"
  >
    <!-- Subtle stage-tinted lane wash (behind cards) -->
    <div class="kanban-column__wash" aria-hidden="true" />

    <!-- Top accent bar -->
    <div class="h-1 w-full shrink-0" :style="{ background: stripGradient }" />

    <!-- Collapsed: thin vertical rail -->
    <button
      v-if="collapsed"
      type="button"
      class="kanban-focusable group flex h-full w-full flex-col items-center gap-3 px-2 py-3"
      :title="stage.name"
      :aria-label="t('KANBAN.STAGES.EXPAND')"
      :aria-expanded="false"
      @click="toggleCollapsed"
    >
      <Icon
        icon="i-lucide-chevrons-right"
        class="size-4 text-n-slate-10 transition group-hover:text-n-slate-12"
      />
      <span
        class="rounded-full bg-n-slate-3 px-1.5 py-0.5 text-[11px] font-semibold text-n-slate-11"
      >
        {{ items.length }}
      </span>
      <span
        class="kanban-column__vertical-label text-sm font-semibold text-n-slate-12"
      >
        {{ stage.name }}
      </span>
    </button>

    <template v-else>
      <div
        class="kanban-column__header sticky top-0 z-10 px-3 py-2.5"
        :style="{ backgroundImage: headerGradient }"
      >
        <div class="group flex items-center justify-between gap-2">
          <div class="flex min-w-0 items-center gap-1">
            <button
              type="button"
              :aria-label="t('KANBAN.STAGES.REORDER_COLUMN')"
              class="kanban-column-drag-handle kanban-focusable -ml-1 cursor-grab rounded-[var(--kanban-radius-md)] p-1 opacity-60 transition hover:bg-n-slate-3/50 hover:opacity-100 active:cursor-grabbing"
            >
              <Icon
                icon="i-lucide-grip-vertical"
                class="size-4 text-n-slate-10"
              />
            </button>

            <h3
              class="truncate text-sm font-semibold leading-tight text-n-slate-12"
            >
              {{ stage.name }}
            </h3>

            <span
              class="rounded-[var(--kanban-radius-sm)] px-2 py-0.5 text-[11px] font-medium transition-colors"
              :class="wipBadgeClass"
              :title="wipTitle"
            >
              {{ cardCount }}{{ wipLimit ? `/${wipLimit}` : '' }}
            </span>
          </div>

          <div class="flex items-center gap-0.5">
            <Button
              size="xs"
              variant="ghost"
              icon="i-lucide-chevrons-left"
              :title="t('KANBAN.STAGES.COLLAPSE')"
              :aria-label="t('KANBAN.STAGES.COLLAPSE')"
              :aria-expanded="!collapsed"
              class="kanban-focusable !size-7 !p-0 rounded-[var(--kanban-radius-md)] text-n-slate-10 opacity-0 transition-opacity hover:bg-n-slate-3/50 group-hover:opacity-100"
              @click.stop="toggleCollapsed"
            />
            <div class="relative">
              <Button
                size="xs"
                variant="ghost"
                icon="i-lucide-more-vertical"
                :aria-label="t('KANBAN.STAGES.TITLE')"
                class="kanban-focusable !size-7 !p-0 rounded-[var(--kanban-radius-md)] text-n-slate-10 opacity-0 transition-opacity hover:bg-n-slate-3/50 group-hover:opacity-100"
                @click.stop="showStageMenu = !showStageMenu"
              />

              <div
                v-if="showStageMenu"
                class="absolute right-0 top-8 z-20 w-48 rounded-xl border border-n-weak bg-n-solid-1 py-1 shadow-lg"
                @click.stop
              >
                <button
                  class="flex w-full items-center gap-2 px-4 py-2 text-left text-sm text-n-slate-11 transition-colors hover:bg-n-solid-3"
                  @click="setWipLimit"
                >
                  <Icon icon="i-lucide-gauge" class="size-4" />
                  {{ t('KANBAN.WIP.SET') }}
                </button>
                <button
                  class="flex w-full items-center gap-2 px-4 py-2 text-left text-sm text-n-slate-11 transition-colors hover:bg-n-solid-3"
                  @click="handleEditStage"
                >
                  <Icon icon="i-lucide-edit" class="size-4" />
                  {{ t('KANBAN.STAGES.EDIT') }}
                </button>
                <button
                  class="flex w-full items-center gap-2 px-4 py-2 text-left text-sm text-ruby-11 transition-colors hover:bg-n-ruby-3"
                  @click="handleDeleteStage"
                >
                  <Icon icon="i-lucide-trash" class="size-4" />
                  {{ t('KANBAN.STAGES.DELETE') }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- WIP load bar -->
      <div v-if="wipLimit" class="h-0.5 w-full shrink-0 bg-n-slate-3/60">
        <div
          class="h-full transition-all duration-300"
          :style="{ width: `${wipBarPct}%`, background: wipBarColor }"
        />
      </div>

      <IntersectionObserver
        v-if="!isStageLoaded || canLoadMore"
        class="h-1 w-full shrink-0"
        @observed="handleColumnObserved"
      />

      <div
        v-if="isLoadingStage && !isStageLoaded"
        role="status"
        aria-busy="true"
        :aria-label="t('KANBAN.LOADING')"
        class="flex flex-1 flex-col gap-2 px-2 py-2"
      >
        <div
          v-for="n in 3"
          :key="`sk-${n}`"
          class="kanban-skeleton h-[92px] w-full"
        />
      </div>

      <draggable
        v-else
        :model-value="itemsWithConversations"
        :group="{ name: 'kanban-items', pull: true, put: true }"
        item-key="id"
        class="kanban-column-content flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto px-2 py-2"
        :animation="180"
        ghost-class="kanban-ghost"
        drag-class="kanban-drag"
        @change="handleDropChange"
      >
        <template #item="{ element: item }">
          <KanbanCard
            :item="item"
            :conversation="item.conversation || {}"
            @move="emit('moveItem', { item })"
            @schedule-message="emit('scheduleMessage', $event)"
            @remove="emit('removeItem', item)"
            @preview="emit('previewConversation', $event)"
          />
        </template>

        <template #footer>
          <div
            v-if="!isStageLoaded && !isLoadingStage"
            class="rounded-lg border border-dashed border-n-weak bg-n-solid-3 px-3 py-5 text-center"
          >
            <p class="mb-3 text-sm text-n-slate-10">
              {{
                isResolvedStage
                  ? t('KANBAN.ITEMS.LOAD_RESOLVED')
                  : t('KANBAN.ITEMS.LOAD_STAGE')
              }}
            </p>
            <Button size="sm" variant="ghost" class="w-full" @click="loadMore">
              {{ t('COMMON.LOAD_MORE') }}
            </Button>
          </div>

          <div
            v-else-if="itemsWithConversations.length === 0"
            class="rounded-lg border border-dashed border-n-weak bg-n-solid-3/60 px-3 py-8 text-center"
          >
            <div
              class="mx-auto mb-2.5 flex size-11 items-center justify-center rounded-full"
              :style="{ backgroundColor: softBg(stage.color, 0.12) }"
            >
              <Icon
                icon="i-lucide-inbox"
                class="size-5"
                :style="{ color: accent(stage.color) }"
              />
            </div>
            <p class="text-sm text-n-slate-10">
              {{ t('KANBAN.ITEMS.NO_ITEMS') }}
            </p>
          </div>

          <IntersectionObserver
            v-if="canLoadMore"
            class="h-1 w-full"
            @observed="handleColumnObserved"
          />

          <div
            v-if="isLoadingStage && isStageLoaded"
            class="flex justify-center py-1"
          >
            <Icon
              icon="i-lucide-loader-2"
              class="size-4 animate-spin text-n-slate-10"
            />
          </div>

          <Button
            v-if="canLoadMore"
            size="sm"
            variant="ghost"
            class="w-full"
            @click="loadMore"
          >
            {{ t('COMMON.LOAD_MORE') }}
          </Button>
        </template>
      </draggable>

      <div
        v-if="isStageLoaded && itemsWithConversations.length"
        class="flex shrink-0 items-center gap-2 border-t border-n-weak px-3 py-1.5 text-[11px] font-medium text-n-slate-10"
      >
        <span>{{ t('KANBAN.FOOTER.CARDS', { count: items.length }) }}</span>
        <span
          v-if="unassignedCount"
          class="flex items-center gap-1 text-n-slate-11"
          :title="t('KANBAN.FOOTER.UNASSIGNED', { count: unassignedCount })"
        >
          <Icon icon="i-lucide-user-x" class="size-3" />
          {{ unassignedCount }}
        </span>
        <span
          v-if="coldCount"
          class="flex items-center gap-1 text-n-ruby-11"
          :title="t('KANBAN.FOOTER.COLD', { count: coldCount })"
        >
          <Icon icon="i-lucide-snowflake" class="size-3" />
          {{ coldCount }}
        </span>
        <span
          v-if="pendingScheduledTotal"
          class="flex items-center gap-1 text-n-teal-11"
        >
          <Icon icon="i-lucide-send" class="size-3" />
          {{ t('KANBAN.FOOTER.SCHEDULED', { count: pendingScheduledTotal }) }}
        </span>
      </div>

      <button
        type="button"
        :aria-label="t('KANBAN.CARD.ADD')"
        class="kanban-focusable flex shrink-0 items-center gap-1 border-t border-n-weak px-3 py-2 text-left text-[11px] font-medium text-n-slate-10 transition hover:bg-n-alpha-1 hover:text-n-slate-12"
        @click="emit('addCard', stage)"
      >
        <Icon icon="i-lucide-plus" class="size-3.5" />
        {{ t('KANBAN.CARD.ADD') }}
      </button>
    </template>
  </div>
</template>

<style scoped>
.kanban-column {
  min-height: 0;
  /* Own stacking context so the -1 wash stays above this column's
     background but below its cards (and never bleeds to siblings). */
  isolation: isolate;
}

/* Lane wash — painted above the column background, below the cards. */
.kanban-column__wash {
  position: absolute;
  inset: 0;
  z-index: -1;
  background: var(--col-wash, transparent);
  pointer-events: none;
}

/* Frosted-glass column header over the stage-tinted gradient. */
.kanban-column__header {
  background-color: var(--kanban-glass-bg);
  backdrop-filter: blur(var(--kanban-glass-blur, 10px));
  -webkit-backdrop-filter: blur(var(--kanban-glass-blur, 10px));
}

.kanban-column--expanded {
  width: var(--kanban-col-width, 304px);
}

.kanban-column--collapsed {
  width: 52px;
  cursor: pointer;
}

.kanban-column__vertical-label {
  writing-mode: vertical-rl;
  text-orientation: mixed;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-height: 60%;
}

.kanban-column-content {
  scrollbar-width: thin;
  scrollbar-color: rgb(var(--border-weak)) transparent;
}

.kanban-column-content::-webkit-scrollbar {
  width: 6px;
}

.kanban-column-content::-webkit-scrollbar-track {
  background: transparent;
}

.kanban-column-content::-webkit-scrollbar-thumb {
  background-color: rgb(var(--border-weak));
  border-radius: 3px;
}

.kanban-column-content::-webkit-scrollbar-thumb:hover {
  background-color: rgb(var(--border-strong));
}
</style>
