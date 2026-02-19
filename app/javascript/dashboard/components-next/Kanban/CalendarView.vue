<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import {
  addDays,
  eachDayOfInterval,
  endOfMonth,
  endOfWeek,
  format,
  isSameDay,
  isToday,
  startOfMonth,
  startOfWeek,
} from 'date-fns';
import { enUS, ptBR } from 'date-fns/locale';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits([
  'createScheduledMessage',
  'editScheduledMessage',
  'cancelScheduledMessage',
]);

const store = useStore();
const router = useRouter();
const { t, locale } = useI18n();

const currentDate = ref(new Date());
const selectedDate = ref(null);
const selectedDayMessages = ref([]);
const selectedDayDate = ref(null);
const showDayDialog = ref(false);

let refreshTimer = null;

const scheduledMessages = computed(
  () => store.getters['kanban/getScheduledMessages']
);
const scheduledMeta = computed(() => store.getters['kanban/getScheduledMeta']);
const scheduledFilters = computed(
  () => store.getters['kanban/getScheduledFilters']
);
const uiFlags = computed(() => store.getters['kanban/getUIFlags']);
const getConversationById = computed(
  () => store.getters['conversations/getConversationById']
);

const calendarLocale = computed(() => {
  return String(locale.value || '').startsWith('pt') ? ptBR : enUS;
});

const isLoading = computed(
  () => uiFlags.value.isFetchingScheduledMessages && !scheduledMeta.value.loaded
);

const dayPreviewLimit = 2;

const monthStart = computed(() => startOfMonth(currentDate.value));
const monthEnd = computed(() => endOfMonth(currentDate.value));
const calendarStart = computed(() =>
  startOfWeek(monthStart.value, { locale: calendarLocale.value })
);
const calendarEnd = computed(() =>
  endOfWeek(monthEnd.value, { locale: calendarLocale.value })
);

const daysInMonth = computed(() =>
  eachDayOfInterval({ start: calendarStart.value, end: calendarEnd.value })
);

const weekDays = computed(() => {
  const weekStart = calendarStart.value;

  return Array.from({ length: 7 }, (_, index) => {
    const day = addDays(weekStart, index);
    const label = format(day, 'EEE', { locale: calendarLocale.value });
    return `${label.charAt(0).toUpperCase()}${label.slice(1)}`;
  });
});

const getConversationFromStore = conversationId => {
  if (!conversationId || typeof getConversationById.value !== 'function') {
    return null;
  }

  return getConversationById.value(Number(conversationId));
};

const getContactInfoForMessage = message => {
  const conversation = getConversationFromStore(message.conversationId);
  const contact = conversation?.meta?.sender || conversation?.contact || {};

  return {
    name:
      contact?.name ||
      `${t('KANBAN.SCHEDULED_MESSAGES.CONVERSATION')} #${
        message.conversationDisplayId || message.conversationId || message.id
      }`,
    phone: contact?.phone_number || contact?.phoneNumber || '',
    avatar: contact?.thumbnail || contact?.avatar_url || contact?.avatar || '',
  };
};

const getMessageStatusLabel = status => {
  const labels = {
    pending: t('KANBAN.SCHEDULED_MESSAGES.STATUS.PENDING'),
    sent: t('KANBAN.SCHEDULED_MESSAGES.STATUS.SENT'),
    failed: t('KANBAN.SCHEDULED_MESSAGES.STATUS.FAILED'),
    cancelled: t('KANBAN.SCHEDULED_MESSAGES.STATUS.CANCELLED'),
  };

  return labels[status] || t('KANBAN.SCHEDULED_MESSAGES.TITLE');
};

const getMessageStatusClass = status => {
  if (status === 'pending') return 'bg-n-blue-9 text-white';
  if (status === 'sent') return 'bg-n-emerald-9 text-white';
  if (status === 'failed') return 'bg-n-ruby-9 text-white';
  return 'bg-n-slate-9 text-white';
};

const canManageMessage = message => message?.status === 'pending';

const getMessagesForDate = date => {
  return scheduledMessages.value
    .filter(message => isSameDay(new Date(message.scheduledAt), date))
    .sort((a, b) => new Date(a.scheduledAt) - new Date(b.scheduledAt));
};

const getPreviewMessagesForDate = date => {
  return getMessagesForDate(date).slice(0, dayPreviewLimit);
};

const getOverflowCountForDate = date => {
  const count = getMessagesForDate(date).length;
  return count > dayPreviewLimit ? count - dayPreviewLimit : 0;
};

const openConversation = message => {
  if (!message?.conversationId && !message?.conversationDisplayId) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.CONVERSATION_NOT_FOUND'));
    return;
  }

  const conversation = getConversationFromStore(message.conversationId);
  const conversationId =
    message.conversationDisplayId ||
    conversation?.displayId ||
    conversation?.display_id ||
    message.conversationId;

  if (!conversationId) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.CONVERSATION_NOT_FOUND'));
    return;
  }

  router.push({
    name: 'inbox_conversation',
    params: { conversation_id: conversationId },
  });
};

const previousMonth = () => {
  currentDate.value = new Date(
    currentDate.value.getFullYear(),
    currentDate.value.getMonth() - 1,
    1
  );
};

const nextMonth = () => {
  currentDate.value = new Date(
    currentDate.value.getFullYear(),
    currentDate.value.getMonth() + 1,
    1
  );
};

const isCurrentMonth = date => date.getMonth() === currentDate.value.getMonth();

const currentCalendarWindow = () => {
  const from = addDays(calendarStart.value, -7);
  const to = addDays(calendarEnd.value, 7);

  return {
    from: from.toISOString(),
    to: to.toISOString(),
  };
};

const loadScheduledMessages = async ({ force = false } = {}) => {
  if (!props.funnelId) return;

  const { from, to } = currentCalendarWindow();
  const alreadyLoadedSameWindow =
    scheduledMeta.value.loaded &&
    scheduledFilters.value.status === 'all' &&
    scheduledFilters.value.from === from &&
    scheduledFilters.value.to === to;

  if (!force && alreadyLoadedSameWindow) return;

  await store.dispatch('kanban/bootstrapScheduledTimeline', {
    status: 'all',
    from,
    to,
    limit: 100,
  });
};

const scheduleCalendarRefresh = ({ force = false } = {}) => {
  if (refreshTimer) {
    clearTimeout(refreshTimer);
    refreshTimer = null;
  }

  refreshTimer = setTimeout(() => {
    loadScheduledMessages({ force });
  }, 220);
};

const openDayDialog = day => {
  selectedDate.value = day;
  selectedDayDate.value = day;
  selectedDayMessages.value = getMessagesForDate(day);
  showDayDialog.value = true;
};

const handleDateClick = day => {
  const dayMessages = getMessagesForDate(day);
  if (dayMessages.length > 0) {
    openDayDialog(day);
    return;
  }

  emit('createScheduledMessage', day);
};

const handleScheduleFromDay = () => {
  if (!selectedDayDate.value) return;
  showDayDialog.value = false;
  emit('createScheduledMessage', selectedDayDate.value);
};

watch(
  () => props.funnelId,
  (newFunnelId, oldFunnelId) => {
    if (!newFunnelId || newFunnelId === oldFunnelId) return;
    scheduleCalendarRefresh({ force: true });
  }
);

watch(currentDate, () => {
  scheduleCalendarRefresh();
});

onMounted(() => {
  scheduleCalendarRefresh({ force: true });
});

onBeforeUnmount(() => {
  if (refreshTimer) {
    clearTimeout(refreshTimer);
    refreshTimer = null;
  }
});
</script>

<template>
  <div class="calendar-view-container h-full w-full overflow-auto p-5">
    <div
      v-if="isLoading && scheduledMessages.length === 0"
      class="flex h-full items-center justify-center"
    >
      <div class="flex flex-col items-center text-center">
        <Icon
          icon="i-lucide-loader-2"
          class="mb-3 size-8 animate-spin text-n-slate-10"
        />
        <p class="text-sm text-n-slate-10">
          {{ t('KANBAN.LOADING_SCHEDULED_MESSAGES') }}
        </p>
      </div>
    </div>

    <div v-else class="mx-auto flex max-w-7xl flex-col gap-4">
      <div
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-2 px-4 py-3"
      >
        <div class="flex items-center gap-2">
          <Button
            variant="ghost"
            icon="i-lucide-chevron-left"
            @click="previousMonth"
          />
          <h2
            class="min-w-[190px] text-center text-lg font-semibold text-n-slate-12"
          >
            {{ format(currentDate, 'MMMM yyyy', { locale: calendarLocale }) }}
          </h2>
          <Button
            variant="ghost"
            icon="i-lucide-chevron-right"
            @click="nextMonth"
          />
        </div>

        <Button
          color="blue"
          icon="i-lucide-plus"
          @click="handleDateClick(new Date())"
        >
          <span class="ml-2">{{ t('KANBAN.SCHEDULED_MESSAGES.CREATE') }}</span>
        </Button>
      </div>

      <div class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-2">
        <div class="grid grid-cols-7 border-b border-n-weak bg-n-solid-3">
          <div
            v-for="day in weekDays"
            :key="day"
            class="px-3 py-2 text-center text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ day }}
          </div>
        </div>

        <div class="grid grid-cols-7">
          <div
            v-for="(day, index) in daysInMonth"
            :key="`${index}-${format(day, 'yyyy-MM-dd')}`"
            class="calendar-day min-h-[132px] border-b border-r border-n-weak p-2.5 transition"
            :class="[
              !isCurrentMonth(day) ? 'bg-n-solid-1 opacity-60' : 'bg-n-solid-2',
              isToday(day) ? 'ring-1 ring-inset ring-n-blue-8' : '',
            ]"
            @click="handleDateClick(day)"
          >
            <div class="mb-2 flex items-center justify-between">
              <span
                class="inline-flex size-6 items-center justify-center rounded-full text-xs font-semibold"
                :class="
                  isToday(day) ? 'bg-n-blue-9 text-white' : 'text-n-slate-11'
                "
              >
                {{ format(day, 'd') }}
              </span>
              <span
                v-if="getMessagesForDate(day).length > 0"
                class="rounded-full bg-n-solid-4 px-2 py-0.5 text-[11px] font-semibold text-n-slate-11"
              >
                {{ getMessagesForDate(day).length }}
              </span>
            </div>

            <div class="space-y-1.5">
              <button
                v-for="message in getPreviewMessagesForDate(day)"
                :key="message.id"
                type="button"
                class="w-full rounded-md border border-n-weak px-2 py-1.5 text-left"
                :class="getMessageStatusClass(message.status)"
                @click.stop="openConversation(message)"
              >
                <div
                  class="flex items-center gap-1.5 text-[11px] font-semibold"
                >
                  <Icon icon="i-lucide-clock" class="size-3" />
                  {{ format(new Date(message.scheduledAt), 'HH:mm') }}
                </div>
                <p class="mt-0.5 truncate text-[11px] font-medium">
                  {{ getContactInfoForMessage(message).name }}
                </p>
              </button>

              <button
                v-if="getOverflowCountForDate(day) > 0"
                type="button"
                class="w-full rounded-md border border-dashed border-n-weak px-2 py-1 text-[11px] font-semibold text-n-slate-10 hover:bg-n-solid-3"
                @click.stop="openDayDialog(day)"
              >
                {{
                  t('KANBAN.SCHEDULED_MESSAGES.MORE_COUNT', {
                    count: getOverflowCountForDate(day),
                  })
                }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <Dialog
      v-if="showDayDialog"
      :show="showDayDialog"
      :title="
        t('KANBAN.SCHEDULED_MESSAGES.DAY_TITLE', {
          date: format(selectedDayDate || new Date(), 'dd MMMM yyyy', {
            locale: calendarLocale,
          }),
        })
      "
      :show-cancel-button="false"
      :show-confirm-button="false"
      width="xl"
      overflow-y-auto
      @close="showDayDialog = false"
    >
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <p class="text-sm text-n-slate-10">
            {{
              t('KANBAN.SCHEDULED_MESSAGES.DAY_COUNT', {
                count: selectedDayMessages.length,
              })
            }}
          </p>

          <Button
            color="blue"
            icon="i-lucide-plus"
            size="sm"
            @click="handleScheduleFromDay"
          >
            <span class="ml-2">{{
              t('KANBAN.SCHEDULED_MESSAGES.SCHEDULE')
            }}</span>
          </Button>
        </div>

        <div class="space-y-2.5">
          <button
            v-for="message in selectedDayMessages"
            :key="message.id"
            type="button"
            class="w-full rounded-lg border border-n-weak bg-n-solid-3 p-3 text-left transition hover:bg-n-solid-4"
            @click="openConversation(message)"
          >
            <div class="flex items-start gap-3">
              <Avatar
                :src="getContactInfoForMessage(message).avatar"
                :name="getContactInfoForMessage(message).name"
                :size="36"
              />

              <div class="min-w-0 flex-1">
                <div class="mb-1 flex items-center gap-2">
                  <span class="text-xs font-semibold text-n-slate-12">
                    {{ format(new Date(message.scheduledAt), 'HH:mm') }}
                  </span>
                  <span
                    class="text-[10px] uppercase tracking-wide text-n-slate-10"
                  >
                    {{ getMessageStatusLabel(message.status) }}
                  </span>
                </div>

                <p class="truncate text-sm font-semibold text-n-slate-12">
                  {{ getContactInfoForMessage(message).name }}
                </p>
                <p
                  v-if="getContactInfoForMessage(message).phone"
                  class="truncate text-xs font-mono text-n-slate-10"
                >
                  {{ getContactInfoForMessage(message).phone }}
                </p>
                <p class="mt-1 truncate text-xs text-n-slate-11">
                  {{
                    message.message || t('KANBAN.SCHEDULED_MESSAGES.NO_TEXT')
                  }}
                </p>

                <div
                  v-if="canManageMessage(message)"
                  class="mt-2 flex items-center justify-end gap-1"
                  @click.stop
                >
                  <Button
                    size="xs"
                    variant="ghost"
                    icon="i-lucide-pencil"
                    :title="t('KANBAN.SCHEDULED_MESSAGES.EDIT')"
                    @click.stop="emit('editScheduledMessage', message)"
                  />
                  <Button
                    size="xs"
                    variant="ghost"
                    color="ruby"
                    icon="i-lucide-trash-2"
                    :title="t('KANBAN.SCHEDULED_MESSAGES.CANCEL')"
                    @click.stop="emit('cancelScheduledMessage', message)"
                  />
                </div>
              </div>
            </div>
          </button>
        </div>
      </div>

      <template #footer>
        <div class="flex w-full items-center justify-end">
          <Button
            :label="t('DIALOG.BUTTONS.CANCEL')"
            variant="link"
            class="h-10"
            @click="showDayDialog = false"
          />
        </div>
      </template>
    </Dialog>
  </div>
</template>

<style scoped>
.calendar-view-container {
  background: var(--n-background);
}

.calendar-day {
  cursor: pointer;
}

.calendar-day:hover {
  background: var(--n-solid-3);
}
</style>
