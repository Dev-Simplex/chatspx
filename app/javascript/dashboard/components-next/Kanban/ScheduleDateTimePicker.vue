<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
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

const formatDateTimeLocal = date => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');
  return `${year}-${month}-${day}T${hours}:${minutes}`;
};

const minimumDateTime = formatDateTimeLocal(new Date());
</script>

<template>
  <div class="space-y-3">
    <div>
      <label class="mb-2 block text-sm font-semibold text-n-slate-12">
        {{ t('KANBAN.SCHEDULED_MESSAGES.SCHEDULED_AT') }}
      </label>
      <input
        :value="scheduledAt"
        type="datetime-local"
        :min="minimumDateTime"
        class="h-11 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 text-sm text-n-slate-12"
        @input="emit('update:scheduledAt', $event.target.value)"
      />
      <p class="mt-1 text-xs text-n-slate-10">
        {{
          t('KANBAN.SCHEDULED_MESSAGES.TIMEZONE', { timezone: timezoneLabel })
        }}
      </p>
    </div>
  </div>
</template>
