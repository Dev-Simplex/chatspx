<script setup>
import { ref, computed, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { formatDistanceToNowStrict } from 'date-fns';
import { enUS, ptBR } from 'date-fns/locale';
import { useMapGetter } from 'dashboard/composables/store';
import { useStageColor } from 'dashboard/components-next/Kanban/composables/useStageColor';
import KanbanAPI from 'dashboard/api/kanban';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const router = useRouter();
const { t, locale } = useI18n();
const { softBg, contrastText } = useStageColor();
const accountId = useMapGetter('getCurrentAccountId');

const items = ref([]);
const isLoading = ref(false);
const hasLoaded = ref(false);

const dateLocale = computed(() =>
  String(locale.value || '').startsWith('pt') ? ptBR : enUS
);

const fetchFunnelItems = async () => {
  if (!props.conversationId) return;
  isLoading.value = true;
  try {
    const { data } = await KanbanAPI.getConversationFunnelItems(
      props.conversationId
    );
    items.value = Array.isArray(data) ? data : [];
  } catch (error) {
    items.value = [];
  } finally {
    isLoading.value = false;
    hasLoaded.value = true;
  }
};

watch(() => props.conversationId, fetchFunnelItems, { immediate: true });

const movedLabel = movedAt => {
  if (!movedAt) return '';
  const date = new Date(movedAt);
  if (Number.isNaN(date.getTime())) return '';
  return formatDistanceToNowStrict(date, {
    addSuffix: true,
    locale: dateLocale.value,
  });
};

const goToFunnel = funnelId => {
  if (!funnelId || !accountId.value) return;
  router.push({
    name: 'kanban_funnel',
    params: { accountId: accountId.value, funnelId },
  });
};
</script>

<template>
  <div class="px-1 pb-1">
    <div v-if="isLoading && !hasLoaded" class="flex justify-center py-3">
      <Icon
        icon="i-lucide-loader-2"
        class="size-4 animate-spin text-n-slate-9"
      />
    </div>

    <div
      v-else-if="!items.length"
      class="flex flex-col items-center gap-1 py-3 text-center"
    >
      <Icon icon="i-lucide-columns-3" class="size-5 text-n-slate-8" />
      <p class="text-xs text-n-slate-10">
        {{ t('CONVERSATION_SIDEBAR.KANBAN_STATUS.EMPTY') }}
      </p>
    </div>

    <ul v-else class="flex flex-col gap-2">
      <li
        v-for="item in items"
        :key="item.id"
        class="kanban-status-row group flex cursor-pointer items-center justify-between gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-2 transition hover:border-n-slate-6 hover:bg-n-solid-2"
        :title="t('CONVERSATION_SIDEBAR.KANBAN_STATUS.OPEN_BOARD')"
        @click="goToFunnel(item.funnel_id)"
      >
        <div class="flex min-w-0 flex-col gap-1">
          <span class="flex items-center gap-1.5 text-xs text-n-slate-10">
            <span
              class="size-2 shrink-0 rounded-full"
              :style="{ backgroundColor: item.funnel_color || '#94a3b8' }"
            />
            <span class="truncate">{{ item.funnel_name }}</span>
          </span>
          <span
            class="inline-flex max-w-max items-center rounded-md px-1.5 py-0.5 text-[11px] font-semibold leading-none"
            :style="{
              backgroundColor: softBg(item.stage_color, 0.16),
              color: contrastText(softBg(item.stage_color, 1)),
            }"
          >
            {{ item.stage_name }}
          </span>
        </div>
        <div class="flex shrink-0 items-center gap-1.5">
          <span
            v-if="movedLabel(item.moved_at)"
            class="text-[11px] text-n-slate-9"
          >
            {{ movedLabel(item.moved_at) }}
          </span>
          <Icon
            icon="i-lucide-arrow-up-right"
            class="size-3.5 text-n-slate-9 opacity-0 transition-opacity group-hover:opacity-100"
          />
        </div>
      </li>
    </ul>
  </div>
</template>
