<script setup>
import { computed, ref, watch } from 'vue';
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
  // When true, cards waiting the longest float to the top of the column.
  prioritizeWaiting: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits([
  'moveItem',
  'reorderItems',
  'scheduleMessage',
  'removeItem',
  'editStage',
  'deleteStage',
  'addCard',
  'previewConversation',
  'editTask',
]);

const store = useStore();
const { t } = useI18n();
const { accent, softBg, heatLevel, slaLevel, waitSignal, waitSortKey } =
  useStageColor();

const showStageMenu = ref(false);
const observerLocked = ref(false);
const lastObservedAt = ref(0);

const headerGradient = computed(
  () =>
    // Softer, shorter tint so dark hues (e.g. violet) don't read heavier than
    // light ones — keeps every stage header balanced in light mode.
    `linear-gradient(180deg, ${softBg(props.stage?.color, 0.1)}, transparent 70%)`
);
const stripGradient = computed(
  () =>
    `linear-gradient(90deg, ${accent(props.stage?.color)}, ${softBg(props.stage?.color, 0.45)})`
);
// Very subtle stage-tinted lane wash behind the cards.
const columnWash = computed(() => softBg(props.stage?.color, 0.05));
// Neon glow color for the top HUD accent bar (stage hue, saturated halo).
const columnGlow = computed(() => softBg(props.stage?.color, 0.85));

const cardCount = computed(() => props.items.length);

// ── WIP limit (per-stage, persisted in funnel_stage.settings) ─────────
// Source of truth is the backend `settings.wip_limit`. The old localStorage
// map is kept only as a soft-migration fallback: stages configured before
// persistence keep their limit and get pushed to the DB on the next edit.
const WIP_KEY = 'kanban:wip';
const readWipMap = () => {
  try {
    return JSON.parse(localStorage.getItem(WIP_KEY) || '{}');
  } catch (_) {
    return {};
  }
};
const coerceWip = raw => {
  const n = Number(raw);
  return Number.isFinite(n) && n >= 1 ? Math.floor(n) : null;
};
const persistedWip = computed(() =>
  coerceWip(props.stage?.settings?.wip_limit)
);

// Per-stage SLA budget (hours-in-stage) → drives conditional card coloring.
const stageSlaHours = computed(() => {
  const n = Number(props.stage?.settings?.sla_hours);
  return Number.isFinite(n) && n > 0 ? n : null;
});

// Custom field definitions (Fase 2): pass show_on_card fields down to cards.
const cardCustomFields = computed(() => {
  const fields = store.getters['kanban/getFunnelCustomFields'](props.funnelId);
  return Array.isArray(fields) ? fields.filter(f => f.showOnCard) : [];
});
const wipLimit = ref(
  persistedWip.value ?? readWipMap()[String(props.stage?.id)] ?? null
);
// Reflect server-side changes (save, reload, real-time) into the local view.
watch(persistedWip, val => {
  if (val !== null) wipLimit.value = val;
});

// WIP limit and stage SLA are configured in the stage editor (StageForm) — a
// polished modal — instead of native window.prompt dialogs.
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

// Numeric custom field aggregates for this stage (sum across all cards).
const stageAggregates = computed(() => {
  const aggregates = stageMeta.value?.aggregates;
  if (!aggregates || typeof aggregates !== 'object') return [];
  return Object.entries(aggregates).map(([key, summary]) => ({
    key,
    label: summary?.label || key,
    sum: Number(summary?.sum ?? 0).toLocaleString(),
  }));
});

// Pull the two timestamps the wait signal needs from a (resolved) conversation.
const waitInputs = conversation => {
  const c = conversation || {};
  return {
    waitingSince: c.waitingSince || c.waiting_since || null,
    lastActivity:
      c.lastActivityAt ||
      c.last_activity_at ||
      c.lastMessage?.created_at ||
      c.last_message?.created_at ||
      null,
  };
};

// Ordem manual persistida (Kanban DB restructure / P1): a base é `position`
// (backfilled para casar com a ordem antiga → mudança invisível até um reorder
// manual). Itens sem position vão para o fim.
const positionOf = item => {
  const p = Number(item?.position);
  return Number.isFinite(p) ? p : Number.MAX_SAFE_INTEGER;
};

const itemsWithConversations = computed(() => {
  const source = props.items || [];
  const mapped = source.map(item => {
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

  // Base order = manual position (ASC), id as a stable tiebreaker.
  const ordered = [...mapped].sort(
    (a, b) => positionOf(a) - positionOf(b) || Number(a.id) - Number(b.id)
  );

  if (!props.prioritizeWaiting) return ordered;

  // Stable sort by wait priority (DESC), preserving the manual position order
  // between cards with equal keys (idx ASC tiebreaker).
  return ordered
    .map((item, idx) => {
      const { waitingSince, lastActivity } = waitInputs(item.conversation);
      return { item, idx, key: waitSortKey(waitingSince, lastActivity) };
    })
    .sort((a, b) => b.key - a.key || a.idx - b.idx)
    .map(entry => entry.item);
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

// Cards where the customer is waiting on a reply (the urgent backlog).
const awaitingCount = computed(
  () =>
    itemsWithConversations.value.filter(item => {
      const { waitingSince, lastActivity } = waitInputs(item.conversation);
      return waitSignal(waitingSince, lastActivity).kind === 'awaiting';
    }).length
);

// Deadline Mode: cards past the stage SLA budget (only when an SLA is set).
const overdueCount = computed(() => {
  if (!stageSlaHours.value) return 0;
  return itemsWithConversations.value.filter(
    item =>
      slaLevel(item.movedAt || item.moved_at, stageSlaHours.value) === 'breach'
  ).length;
});

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
  const stageId = Number(props.stage?.id);

  // Same-column reorder → persist the new manual order (survives reload).
  if (evt?.moved?.element?.id != null) {
    const { oldIndex, newIndex } = evt.moved;
    if (oldIndex == null || newIndex == null || oldIndex === newIndex) return;
    const ids = itemsWithConversations.value
      .map(i => Number(i.id))
      .filter(Boolean);
    const [moved] = ids.splice(oldIndex, 1);
    ids.splice(newIndex, 0, moved);
    emit('reorderItems', { stageId, orderedIds: ids });
    return;
  }

  // Cross-stage drop keeps the existing move flow (changes the card's stage).
  const payload = resolveDropPayload(evt);
  if (!payload) return;
  emit('moveItem', { ...payload, stageId });
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
    class="kanban-column relative flex h-full flex-shrink-0 flex-col overflow-hidden rounded-[var(--kanban-radius-xl)] bg-n-slate-2/80 dark:bg-n-solid-2"
    :class="collapsed ? 'kanban-column--collapsed' : 'kanban-column--expanded'"
    :style="{ '--col-wash': columnWash, '--hud-glow': columnGlow }"
  >
    <!-- Subtle stage-tinted lane wash (behind cards) -->
    <div class="kanban-column__wash" aria-hidden="true" />

    <!-- Top accent bar — neon HUD glow in the stage hue -->
    <div
      class="kanban-column__accent h-1 w-full shrink-0"
      :style="{ background: stripGradient }"
    />

    <!-- Collapsed: thin vertical rail -->
    <button
      v-if="collapsed"
      v-tooltip="stage.name"
      type="button"
      class="kanban-focusable group flex h-full w-full flex-col items-center gap-3 px-2 py-3"
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
              v-tooltip="wipTitle"
              class="rounded-[var(--kanban-radius-sm)] px-2 py-0.5 text-[11px] font-medium transition-colors"
              :class="wipBadgeClass"
            >
              {{ cardCount }}{{ wipLimit ? `/${wipLimit}` : '' }}
            </span>
          </div>

          <div class="flex items-center gap-0.5">
            <Button
              v-tooltip="t('KANBAN.STAGES.COLLAPSE')"
              size="xs"
              variant="ghost"
              icon="i-lucide-chevrons-left"
              :aria-label="t('KANBAN.STAGES.COLLAPSE')"
              :aria-expanded="!collapsed"
              class="kanban-focusable !size-7 !p-0 rounded-[var(--kanban-radius-md)] text-n-slate-10 transition-opacity hover:bg-n-slate-3/50 md:opacity-0 md:group-hover:opacity-100"
              @click.stop="toggleCollapsed"
            />
            <div class="relative">
              <Button
                size="xs"
                variant="ghost"
                icon="i-lucide-more-vertical"
                :aria-label="t('KANBAN.STAGES.TITLE')"
                class="kanban-focusable !size-7 !p-0 rounded-[var(--kanban-radius-md)] text-n-slate-10 transition-opacity hover:bg-n-slate-3/50 md:opacity-0 md:group-hover:opacity-100"
                @click.stop="showStageMenu = !showStageMenu"
              />

              <template v-if="showStageMenu">
                <div
                  class="fixed inset-0 z-20"
                  @click="showStageMenu = false"
                />
                <div
                  class="absolute right-0 top-8 z-30 w-48 rounded-[var(--kanban-radius-xl)] border border-n-weak bg-n-solid-1 py-1 shadow-lg"
                  @click.stop
                >
                  <button
                    class="flex w-full items-center gap-2 px-4 py-2 text-left text-sm text-n-slate-11 transition-colors hover:bg-n-solid-3"
                    @click="handleEditStage"
                  >
                    <Icon icon="i-lucide-edit" class="size-4" />
                    {{ t('KANBAN.STAGES.EDIT') }}
                  </button>
                  <button
                    class="flex w-full items-center gap-2 px-4 py-2 text-left text-sm text-n-ruby-11 transition-colors hover:bg-n-ruby-3"
                    @click="handleDeleteStage"
                  >
                    <Icon icon="i-lucide-trash" class="size-4" />
                    {{ t('KANBAN.STAGES.DELETE') }}
                  </button>
                </div>
              </template>
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
            :stage-color="stage.color"
            :sla-hours="stageSlaHours"
            :custom-fields="cardCustomFields"
            @move="emit('moveItem', { item })"
            @schedule-message="emit('scheduleMessage', $event)"
            @remove="emit('removeItem', item)"
            @preview="emit('previewConversation', $event)"
            @edit-task="emit('editTask', $event)"
          />
        </template>

        <template #footer>
          <div
            v-if="!isStageLoaded && !isLoadingStage"
            class="rounded-[var(--kanban-radius-lg)] border border-dashed border-n-weak bg-n-solid-3 px-3 py-5 text-center"
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
            class="rounded-[var(--kanban-radius-lg)] border border-dashed border-n-slate-5 bg-n-slate-2 dark:border-n-weak dark:bg-n-solid-3/60 px-3 py-8 text-center"
          >
            <div
              class="mx-auto mb-2.5 flex size-11 items-center justify-center rounded-full"
              :style="{ backgroundColor: softBg(stage.color, 0.18) }"
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
          v-if="awaitingCount"
          v-tooltip="t('KANBAN.FOOTER.AWAITING', { count: awaitingCount })"
          class="flex items-center gap-1 font-semibold text-n-ruby-11"
        >
          <Icon icon="i-lucide-bell-ring" class="size-3" />
          {{ awaitingCount }}
        </span>
        <span
          v-if="unassignedCount"
          v-tooltip="t('KANBAN.FOOTER.UNASSIGNED', { count: unassignedCount })"
          class="flex items-center gap-1 text-n-slate-11"
        >
          <Icon icon="i-lucide-user-x" class="size-3" />
          {{ unassignedCount }}
        </span>
        <span
          v-if="coldCount"
          v-tooltip="t('KANBAN.FOOTER.COLD', { count: coldCount })"
          class="flex items-center gap-1 text-n-ruby-11"
        >
          <Icon icon="i-lucide-snowflake" class="size-3" />
          {{ coldCount }}
        </span>
        <span
          v-if="overdueCount"
          v-tooltip="t('KANBAN.FOOTER.OVERDUE', { count: overdueCount })"
          class="flex items-center gap-1 font-semibold text-n-ruby-11"
        >
          <Icon icon="i-lucide-gauge" class="size-3" />
          {{ overdueCount }}
        </span>
        <span
          v-if="pendingScheduledTotal"
          class="flex items-center gap-1 text-n-teal-11"
        >
          <Icon icon="i-lucide-send" class="size-3" />
          {{ t('KANBAN.FOOTER.SCHEDULED', { count: pendingScheduledTotal }) }}
        </span>
      </div>

      <!-- Numeric custom field totals (Fase 2) -->
      <div
        v-if="stageAggregates.length && isStageLoaded"
        class="flex shrink-0 flex-wrap items-center gap-x-3 gap-y-0.5 border-t border-n-weak px-3 py-1.5 text-[11px] text-n-slate-11"
      >
        <span
          v-for="agg in stageAggregates"
          :key="agg.key"
          v-tooltip="`${agg.label}: ${agg.sum}`"
          class="flex items-center gap-1"
        >
          <Icon icon="i-lucide-sigma" class="size-3 text-n-slate-10" />
          <span class="truncate">{{ agg.label }}:</span>
          <span class="font-semibold text-n-slate-12">{{ agg.sum }}</span>
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

/* Neon HUD accent — the top bar emits a saturated colored halo downward into
   the header (clipped upward by the column's overflow, so it reads as emitted
   light), and breathes via a subtle glow pulse. */
.kanban-column__accent {
  position: relative;
  z-index: 1;
  /* Light: soft colored edge; dark keeps the full breathing neon below. */
  box-shadow: 0 1px 4px 0 var(--hud-glow, transparent);
}

:global(.dark) .kanban-column__accent {
  box-shadow:
    0 1px 7px 0 var(--hud-glow, transparent),
    0 0 16px 0 var(--hud-glow, transparent);
  animation: kanban-neon-pulse 2.6s ease-in-out infinite;
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
  /* Hairline under the sticky header so it stays defined while cards scroll
     beneath it (box-shadow, not border, to avoid any layout shift). */
  box-shadow: 0 1px 0 0 var(--kanban-column-border, transparent);
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
