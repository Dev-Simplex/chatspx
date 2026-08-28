<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, formatDistanceStrict } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  scheduledAt: {
    type: String,
    default: '',
  },
  timezoneLabel: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:scheduledAt']);
const { t } = useI18n();

const firstChipRef = ref(null);
const now = ref(new Date());

let tickInterval = null;
onMounted(() => {
  tickInterval = setInterval(() => {
    now.value = new Date();
  }, 30000);
});
onUnmounted(() => {
  if (tickInterval) clearInterval(tickInterval);
});

const pad = n => String(n).padStart(2, '0');

const dateToLocalInput = date => {
  const y = date.getFullYear();
  const m = pad(date.getMonth() + 1);
  const d = pad(date.getDate());
  const h = pad(date.getHours());
  const min = pad(date.getMinutes());
  return `${y}-${m}-${d}T${h}:${min}`;
};

const minimumDateTime = computed(() => dateToLocalInput(now.value));

const buildDate = (offsetDays, hour, minute = 0) => {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  d.setHours(hour, minute, 0, 0);
  return d;
};

const inOneHour = () => {
  const d = new Date();
  d.setHours(d.getHours() + 1);
  d.setSeconds(0, 0);
  return d;
};

const tonightAt = (hour = 20) => {
  const d = new Date();
  if (d.getHours() >= hour) {
    // already past tonight, push to tomorrow night
    d.setDate(d.getDate() + 1);
  }
  d.setHours(hour, 0, 0, 0);
  return d;
};

const tomorrowMorning = () => buildDate(1, 9, 0);

const nextMonday = () => {
  const d = new Date();
  const day = d.getDay(); // 0=Sun..6=Sat
  const diff = (1 - day + 7) % 7 || 7; // always next Monday, never today
  d.setDate(d.getDate() + diff);
  d.setHours(9, 0, 0, 0);
  return d;
};

const quickOptions = computed(() => [
  {
    key: 'inOneHour',
    label: t('KANBAN.SCHEDULED_MESSAGES.QUICK_IN_ONE_HOUR'),
    icon: 'i-lucide-zap',
    build: inOneHour,
  },
  {
    key: 'tonight',
    label: t('KANBAN.SCHEDULED_MESSAGES.QUICK_TONIGHT'),
    icon: 'i-lucide-moon',
    build: () => tonightAt(20),
  },
  {
    key: 'tomorrow',
    label: t('KANBAN.SCHEDULED_MESSAGES.QUICK_TOMORROW'),
    icon: 'i-lucide-sunrise',
    build: tomorrowMorning,
  },
  {
    key: 'nextMonday',
    label: t('KANBAN.SCHEDULED_MESSAGES.QUICK_NEXT_MONDAY'),
    icon: 'i-lucide-calendar-days',
    build: nextMonday,
  },
]);

const applyQuickOption = option => {
  const date = option.build();
  emit('update:scheduledAt', dateToLocalInput(date));
};

const parsedScheduled = computed(() => {
  if (!props.scheduledAt) return null;
  const d = new Date(props.scheduledAt);
  return Number.isNaN(d.getTime()) ? null : d;
});

const isPastOrTooSoon = computed(() => {
  if (!parsedScheduled.value) return false;
  // require at least 1 minute in the future
  return parsedScheduled.value.getTime() - now.value.getTime() < 60 * 1000;
});

const matchedQuickKey = computed(() => {
  if (!parsedScheduled.value) return null;
  const target = parsedScheduled.value.getTime();
  const match = quickOptions.value.find(
    opt => Math.abs(opt.build().getTime() - target) < 60 * 1000
  );
  return match?.key || null;
});

const formatRelative = date => {
  try {
    return formatDistanceStrict(date, now.value, {
      locale: ptBR,
      roundingMethod: 'floor',
    });
  } catch (_) {
    return '';
  }
};

const formatAbsolute = date => {
  try {
    return format(date, "EEE, d MMM yyyy '·' HH:mm", { locale: ptBR });
  } catch (_) {
    return '';
  }
};

const previewRelative = computed(() => {
  if (!parsedScheduled.value) return '';
  return formatRelative(parsedScheduled.value);
});

const previewAbsolute = computed(() => {
  if (!parsedScheduled.value) return '';
  return formatAbsolute(parsedScheduled.value);
});

defineExpose({
  focusFirstQuickOption: () => firstChipRef.value?.focus?.(),
});
</script>

<template>
  <div class="space-y-3">
    <div>
      <label class="mb-2 block text-sm font-semibold text-n-slate-12">
        {{ t('KANBAN.SCHEDULED_MESSAGES.WHEN_TO_SEND') }}
      </label>
      <p class="mb-3 text-xs text-n-slate-10">
        {{ t('KANBAN.SCHEDULED_MESSAGES.WHEN_TO_SEND_HINT') }}
      </p>

      <div class="mb-3 flex flex-wrap gap-2">
        <button
          v-for="(option, index) in quickOptions"
          :key="option.key"
          :ref="
            el => {
              if (index === 0) firstChipRef = el;
            }
          "
          type="button"
          class="inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            matchedQuickKey === option.key
              ? 'border-n-brand bg-n-brand/10 text-n-brand'
              : 'border-n-weak bg-n-solid-2 text-n-slate-12 hover:bg-n-solid-3'
          "
          @click="applyQuickOption(option)"
        >
          <Icon :icon="option.icon" class="size-3.5" />
          {{ option.label }}
        </button>
      </div>

      <div>
        <label
          for="scheduled-message-datetime"
          class="mb-1.5 block text-xs font-medium text-n-slate-11"
        >
          {{ t('KANBAN.SCHEDULED_MESSAGES.OR_PICK_CUSTOM') }}
        </label>
        <input
          id="scheduled-message-datetime"
          :value="scheduledAt"
          type="datetime-local"
          :min="minimumDateTime"
          class="h-11 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          @input="emit('update:scheduledAt', $event.target.value)"
        />
      </div>
    </div>

    <div
      v-if="parsedScheduled"
      class="rounded-lg border px-3 py-2.5 text-sm"
      :class="
        isPastOrTooSoon
          ? 'border-n-amber-6 bg-n-amber-3 text-n-amber-12 dark:bg-n-amber-9/10'
          : 'border-n-teal-6 bg-n-teal-3 text-n-teal-12 dark:bg-n-teal-9/10'
      "
    >
      <div v-if="isPastOrTooSoon" class="flex items-start gap-2">
        <Icon icon="i-lucide-alert-triangle" class="mt-0.5 size-4 shrink-0" />
        <span>{{ t('KANBAN.SCHEDULED_MESSAGES.PREVIEW_TOO_SOON') }}</span>
      </div>
      <div v-else class="flex items-start gap-2">
        <Icon icon="i-lucide-check-circle-2" class="mt-0.5 size-4 shrink-0" />
        <span>
          <strong>
            {{
              t('KANBAN.SCHEDULED_MESSAGES.PREVIEW_WILL_SEND_IN', {
                duration: previewRelative,
              })
            }}
          </strong>
          <span class="ml-1 opacity-80">{{ previewAbsolute }}</span>
        </span>
      </div>
    </div>

    <p v-if="timezoneLabel" class="text-xs text-n-slate-10">
      {{
        t('KANBAN.SCHEDULED_MESSAGES.TIMEZONE_HINT', {
          timezone: timezoneLabel,
        })
      }}
    </p>
  </div>
</template>
