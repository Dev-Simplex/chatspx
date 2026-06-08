<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import draggable from 'vuedraggable';
import KanbanCard from './KanbanCard.vue';
import KanbanInlineComposer from './KanbanInlineComposer.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';

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
  // P2-07: ativa modo seleção múltipla.
  bulkMode: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'moveItem',
  'scheduleMessage',
  'removeItem',
  'editStage',
  'deleteStage',
  'openDrawer',
]);

const store = useStore();
const { t } = useI18n();

const showStageMenu = ref(false);
const observerLocked = ref(false);
const lastObservedAt = ref(0);

const isResolvedStage = computed(() => {
  const type = props.stage?.automationType ?? props.stage?.automation_type;
  if (type === 'resolved') return true;
  const name = (props.stage?.name || '').toLowerCase();
  return name === 'resolvido' || name === 'resolved';
});

// P3-08: WIP limit derivado da stage.
const wipLimit = computed(
  () => Number(props.stage?.wipLimit || props.stage?.wip_limit || 0) || 0
);

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
    class="kanban-column flex h-full w-[300px] flex-shrink-0 flex-col rounded-xl bg-n-slate-2/50 dark:bg-n-solid-2"
  >
    <div class="sticky top-0 z-10 px-4 py-3">
      <div class="group flex items-center justify-between gap-2">
        <div class="flex min-w-0 items-center gap-2">
          <div
            class="kanban-column-drag-handle -ml-1 cursor-grab rounded-lg p-1 opacity-60 transition hover:bg-n-slate-3/50 hover:opacity-100 active:cursor-grabbing"
          >
            <Icon icon="i-lucide-grip-vertical" class="size-4 text-n-slate-9" />
          </div>

          <div
            v-if="stage.color"
            class="h-2.5 w-2.5 shrink-0 rounded-full"
            :style="{ backgroundColor: stage.color }"
          />

          <h3 class="truncate text-sm font-semibold text-n-slate-12">
            {{ stage.name }}
          </h3>

          <span
            class="rounded-full px-2 py-0.5 text-xs"
            :class="
              wipLimit && items.length > wipLimit
                ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300 font-semibold'
                : wipLimit && items.length >= wipLimit
                  ? 'bg-amber-50 text-amber-700 dark:bg-amber-900/20 dark:text-amber-300'
                  : 'bg-n-slate-3 text-n-slate-10'
            "
            :title="
              wipLimit ? `${items.length} / ${wipLimit}` : `${items.length}`
            "
          >
            <Icon
              v-if="wipLimit && items.length > wipLimit"
              icon="i-lucide-alert-triangle"
              class="size-3 -mt-0.5 inline"
            />
            {{ wipLimit ? `${items.length}/${wipLimit}` : items.length }}
          </span>
        </div>

        <div class="relative">
          <Button
            size="xs"
            variant="ghost"
            icon="i-lucide-more-vertical"
            class="!size-7 !p-0 rounded-lg hover:bg-n-slate-3/50 text-n-slate-10 opacity-0 transition-opacity group-hover:opacity-100"
            @click.stop="showStageMenu = !showStageMenu"
          />

          <div
            v-if="showStageMenu"
            class="absolute right-0 top-8 z-20 w-48 rounded-xl border border-n-weak bg-n-solid-1 py-1 shadow-lg"
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

    <IntersectionObserver
      v-if="!isStageLoaded || canLoadMore"
      class="h-1 w-full shrink-0"
      @observed="handleColumnObserved"
    />

    <div
      v-if="isLoadingStage && !isStageLoaded"
      class="flex justify-center py-4"
    >
      <Icon
        icon="i-lucide-loader-2"
        class="size-5 animate-spin text-n-slate-9"
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
          :stage="stage"
          :stage-name="stage.name"
          :stage-color="stage.color"
          :bulk-mode="bulkMode"
          @move="emit('moveItem', { item })"
          @schedule-message="emit('scheduleMessage', $event)"
          @remove="emit('removeItem', item)"
          @open-drawer="emit('openDrawer', item)"
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
          class="rounded-lg border border-dashed border-n-weak bg-n-solid-3 px-3 py-8 text-center"
        >
          <Icon
            icon="i-lucide-inbox"
            class="mx-auto mb-2 size-8 text-n-slate-8"
          />
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
            class="size-4 animate-spin text-n-slate-9"
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

    <!-- P1-05: composer inline no final da coluna -->
    <KanbanInlineComposer
      :funnel-id="funnelId"
      :stage-id="stage.id"
      :stage-name="stage.name"
    />
  </div>
</template>

<style scoped>
.kanban-column {
  min-height: 0;
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

:deep(.kanban-ghost) {
  opacity: 0.3;
  border: 2px dashed #2dc46f;
  border-radius: 0.75rem;
  background: rgba(45, 196, 111, 0.05);
}

:deep(.kanban-drag) {
  opacity: 0.95;
  box-shadow:
    0 20px 25px -5px rgba(0, 0, 0, 0.15),
    0 8px 10px -6px rgba(0, 0, 0, 0.1);
  transform: rotate(1deg);
}
</style>
