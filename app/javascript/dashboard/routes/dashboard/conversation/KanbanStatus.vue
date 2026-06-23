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
const { accent, softBg, contrastText } = useStageColor();
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

    <ul v-else class="flex flex-col gap-2.5">
      <li
        v-for="item in items"
        :key="item.id"
        class="kanban-status-card group relative flex cursor-pointer flex-col gap-2.5 overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 py-2.5 pl-3.5 pr-2.5 transition hover:border-n-slate-6 hover:bg-n-solid-2 hover:shadow-sm"
        :title="t('CONVERSATION_SIDEBAR.KANBAN_STATUS.OPEN_BOARD')"
        @click="goToFunnel(item.funnel_id)"
      >
        <!-- Faixa de cor do funil, identidade visual instantânea -->
        <span
          class="absolute inset-y-0 left-0 w-1.5"
          :style="{ backgroundColor: accent(item.funnel_color) }"
        />

        <!-- Funil -->
        <div class="flex items-center gap-2">
          <span
            class="flex size-6 shrink-0 items-center justify-center rounded-md"
            :style="{ backgroundColor: softBg(item.funnel_color, 0.16) }"
          >
            <Icon
              icon="i-lucide-filter"
              class="size-3.5"
              :style="{ color: accent(item.funnel_color) }"
            />
          </span>
          <span class="truncate text-sm font-medium text-n-slate-12">
            {{ item.funnel_name }}
          </span>
        </div>

        <!-- Estágio (status em destaque) + quando mudou -->
        <div class="flex items-center justify-between gap-2">
          <span
            class="inline-flex max-w-max items-center rounded-full px-2.5 py-1 text-xs font-semibold leading-none shadow-sm"
            :style="{
              backgroundColor: accent(item.stage_color),
              color: contrastText(item.stage_color),
            }"
          >
            {{ item.stage_name }}
          </span>
          <span
            v-if="movedLabel(item.moved_at)"
            class="flex shrink-0 items-center gap-1 text-[11px] text-n-slate-10"
          >
            <Icon icon="i-lucide-clock-3" class="size-3" />
            {{ movedLabel(item.moved_at) }}
          </span>
        </div>

        <!-- Ação: abrir no board -->
        <div
          class="flex items-center gap-1 border-t border-n-weak pt-2 text-[11px] font-medium text-n-slate-11 transition-colors group-hover:text-n-brand"
        >
          <Icon icon="i-lucide-external-link" class="size-3" />
          {{ t('CONVERSATION_SIDEBAR.KANBAN_STATUS.OPEN_BOARD') }}
        </div>
      </li>
    </ul>
  </div>
</template>
