<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { dateFormat, shortTimeAgo } from 'shared/helpers/timeHelper';
import { useTimeAgo } from 'dashboard/composables/useTimeAgo';

const props = defineProps({
  lastActivityTimestamp: {
    type: [String, Date, Number],
    default: '',
  },
  createdAtTimestamp: {
    type: [String, Date, Number],
    default: '',
  },
});

const DAY_IN_MILLI_SECONDS = 86400000;

const { t } = useI18n();

const { lastActivityDisplay, createdAtDisplay, update } = useTimeAgo(
  props.lastActivityTimestamp,
  props.createdAtTimestamp
);

watch(
  () => [props.lastActivityTimestamp, props.createdAtTimestamp],
  ([newLastActivity, newCreatedAt]) => {
    update(newLastActivity, newCreatedAt);
  }
);

const lastActivityTime = computed(() => {
  // le lastActivityDisplay (atualizado pelo timer do useTimeAgo) para criar a
  // dependencia reativa e recalcular o compacto ao vivo a cada tick.
  const tick = lastActivityDisplay.value;
  return tick ? shortTimeAgo(props.lastActivityTimestamp) : '';
});

const createdAt = computed(() => {
  const createdTimeDiff = Date.now() - props.createdAtTimestamp * 1000;
  const isBeforeAMonth = createdTimeDiff > DAY_IN_MILLI_SECONDS * 30;
  return !isBeforeAMonth
    ? `${t('CHAT_LIST.CHAT_TIME_STAMP.CREATED.LATEST')} ${createdAtDisplay.value}`
    : `${t('CHAT_LIST.CHAT_TIME_STAMP.CREATED.OLDEST')} ${dateFormat(props.createdAtTimestamp)}`;
});

const lastActivity = computed(() => {
  const lastActivityTimeDiff = Date.now() - props.lastActivityTimestamp * 1000;
  const isNotActive = lastActivityTimeDiff > DAY_IN_MILLI_SECONDS * 30;
  return !isNotActive
    ? `${t('CHAT_LIST.CHAT_TIME_STAMP.LAST_ACTIVITY.ACTIVE')} ${lastActivityDisplay.value}`
    : `${t('CHAT_LIST.CHAT_TIME_STAMP.LAST_ACTIVITY.NOT_ACTIVE')} ${dateFormat(props.lastActivityTimestamp)}`;
});

const tooltipText = computed(
  () => `${createdAt.value} | ${lastActivity.value}`
);
</script>

<template>
  <div
    v-tooltip.top="{
      content: tooltipText,
      delay: { show: 1000, hide: 0 },
    }"
    class="ml-auto leading-4 text-xxs text-n-slate-10 hover:text-n-slate-11"
  >
    <span>{{ lastActivityTime }}</span>
  </div>
</template>
