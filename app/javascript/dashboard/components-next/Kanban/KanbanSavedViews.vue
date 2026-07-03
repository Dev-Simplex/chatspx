<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();

const activeFunnelId = useMapGetter('kanban/getActiveFunnelId');
const savedViews = useMapGetter('kanban/getSavedViews');
const viewFilters = useMapGetter('kanban/getViewFilters');
const viewMode = useMapGetter('kanban/getViewMode');
const currentUserId = useMapGetter('getCurrentUserID');

const open = ref(false);
const isBusy = ref(false);
const rootRef = ref(null);

const funnelViews = computed(() =>
  (savedViews.value || []).filter(
    view => Number(view.funnel_id) === Number(activeFunnelId.value)
  )
);

const load = () => {
  if (!activeFunnelId.value) return;
  store
    .dispatch('kanban/fetchSavedViews', activeFunnelId.value)
    .catch(() => {});
};
onMounted(load);
watch(activeFunnelId, load);

const applyView = view => {
  store.dispatch('kanban/applySavedView', view);
  open.value = false;
};

const saveCurrent = async () => {
  // eslint-disable-next-line no-alert
  const name = window.prompt(t('KANBAN.SAVED_VIEWS.NAME_PROMPT'));
  if (!name || !name.trim() || !activeFunnelId.value) return;
  isBusy.value = true;
  try {
    await store.dispatch('kanban/createSavedView', {
      funnel_id: activeFunnelId.value,
      name: name.trim(),
      view_mode: viewMode.value,
      filters: viewFilters.value,
    });
    open.value = false;
  } catch (_) {
    useAlert(t('KANBAN.SAVED_VIEWS.SAVE_ERROR'));
  } finally {
    isBusy.value = false;
  }
};

const removeView = async view => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(t('KANBAN.SAVED_VIEWS.DELETE_CONFIRM', { name: view.name }))
  )
    return;
  try {
    await store.dispatch('kanban/deleteSavedView', view.id);
  } catch (_) {
    useAlert(t('KANBAN.SAVED_VIEWS.SAVE_ERROR'));
  }
};

const canDelete = view => Number(view.user_id) === Number(currentUserId.value);

const onClickOutside = event => {
  if (rootRef.value && !rootRef.value.contains(event.target))
    open.value = false;
};
onMounted(() => document.addEventListener('click', onClickOutside));
onBeforeUnmount(() => document.removeEventListener('click', onClickOutside));
</script>

<template>
  <div ref="rootRef" class="relative">
    <Button
      variant="ghost"
      size="sm"
      icon="i-lucide-bookmark"
      class="kanban-filter-action !h-10 lg:w-auto"
      :title="t('KANBAN.SAVED_VIEWS.TITLE')"
      @click.stop="open = !open"
    >
      <span class="ml-2 hidden lg:inline">{{
        t('KANBAN.SAVED_VIEWS.TITLE')
      }}</span>
      <span
        v-if="funnelViews.length"
        class="ml-2 inline-flex min-w-5 items-center justify-center rounded-full bg-n-slate-3 px-1.5 text-[11px] font-semibold text-n-slate-11"
      >
        {{ funnelViews.length }}
      </span>
    </Button>

    <div
      v-if="open"
      class="absolute right-0 top-11 z-30 w-64 rounded-xl border border-n-weak bg-n-solid-1 py-1 shadow-lg"
      @click.stop
    >
      <p v-if="!funnelViews.length" class="px-3 py-2 text-xs text-n-slate-10">
        {{ t('KANBAN.SAVED_VIEWS.EMPTY') }}
      </p>
      <ul v-else class="max-h-64 overflow-y-auto">
        <li
          v-for="view in funnelViews"
          :key="view.id"
          class="group flex items-center gap-2 px-2 py-1.5 hover:bg-n-solid-3"
        >
          <button
            type="button"
            class="flex min-w-0 flex-1 items-center gap-2 text-left text-sm text-n-slate-12"
            @click="applyView(view)"
          >
            <Icon
              :icon="view.is_shared ? 'i-lucide-users' : 'i-lucide-user'"
              class="size-3.5 shrink-0 text-n-slate-10"
            />
            <span class="truncate">{{ view.name }}</span>
          </button>
          <button
            v-if="canDelete(view)"
            type="button"
            class="shrink-0 rounded p-1 text-n-slate-10 opacity-0 transition hover:bg-n-ruby-3 hover:text-n-ruby-11 group-hover:opacity-100"
            :title="t('KANBAN.SAVED_VIEWS.DELETE')"
            @click.stop="removeView(view)"
          >
            <Icon icon="i-lucide-trash-2" class="size-3.5" />
          </button>
        </li>
      </ul>
      <div class="mt-1 border-t border-n-weak pt-1">
        <button
          type="button"
          class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm font-medium text-n-brand transition hover:bg-n-solid-3 disabled:opacity-50"
          :disabled="isBusy || !activeFunnelId"
          @click="saveCurrent"
        >
          <Icon icon="i-lucide-plus" class="size-3.5" />
          {{ t('KANBAN.SAVED_VIEWS.SAVE_CURRENT') }}
        </button>
      </div>
    </div>
  </div>
</template>
