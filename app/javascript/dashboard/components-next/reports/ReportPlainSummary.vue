<script setup>
import { ref, computed } from 'vue';
import { useI18n, I18nT } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { STATUS } from 'dashboard/store/constants';
import { formatDuration } from 'dashboard/helper/reportFormat';
import ReportDrilldownPanel from './ReportDrilldownPanel.vue';

// O relatorio de Conversas em tres frases, para quem nao le grafico. Cada numero abre as conversas por
// tras dele (o mesmo painel dos cartoes).
const props = defineProps({
  accountSummaryKey: { type: String, default: 'getAccountSummary' },
  summaryFetchingKey: {
    type: String,
    default: 'getAccountSummaryFetchingStatus',
  },
  // { from, to, type, id, businessHours, inboxId }
  drilldownFilters: { type: Object, default: null },
});

const { t } = useI18n();
const summary = useMapGetter(props.accountSummaryKey);
const fetchingStatus = useMapGetter(props.summaryFetchingKey);

const isReady = computed(
  () =>
    fetchingStatus.value === STATUS.FINISHED &&
    Number(summary.value?.conversations_count) > 0
);

const count = key => Number(summary.value?.[key] || 0).toLocaleString();
const time = key => formatDuration(summary.value?.[key], t);

const hasFirstResponse = computed(
  () => Number(summary.value?.first_response_count) > 0
);
const hasResolutions = computed(
  () => Number(summary.value?.resolutions_count) > 0
);

const drilldown = ref(null);
const open = (key, nameKey) => {
  if (!props.drilldownFilters) return;
  drilldown.value = { key, name: t(nameKey) };
};
</script>

<template>
  <section
    v-if="isReady"
    class="mt-4 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] p-5"
  >
    <h3
      class="m-0 text-[15px] font-extrabold tracking-[-0.015em] text-n-slate-12"
    >
      {{ t('REPORT.PLAIN_SUMMARY.TITLE') }}
    </h3>
    <ul
      class="mt-3 flex flex-col gap-3 text-base leading-relaxed text-n-slate-12"
    >
      <li class="flex gap-3">
        <span
          class="i-lucide-message-circle size-5 mt-1 shrink-0 text-n-brand"
        />
        <span class="min-w-0">
          <I18nT keypath="REPORT.PLAIN_SUMMARY.VOLUME" tag="span">
            <template #conversations>
              <button
                type="button"
                class="inline p-0 m-0 align-baseline text-[length:inherit] leading-[inherit] font-semibold underline decoration-dotted underline-offset-4 hover:text-n-brand"
                @click="
                  open(
                    'conversations_count',
                    'REPORT.METRICS.CONVERSATIONS.NAME'
                  )
                "
              >
                {{
                  t('REPORT.PLAIN_SUMMARY.CONVERSATIONS', {
                    count: count('conversations_count'),
                  })
                }}
              </button>
            </template>
            <template #incoming>
              <button
                type="button"
                class="inline p-0 m-0 align-baseline text-[length:inherit] leading-[inherit] font-semibold underline decoration-dotted underline-offset-4 hover:text-n-brand"
                @click="
                  open(
                    'incoming_messages_count',
                    'REPORT.METRICS.INCOMING_MESSAGES.NAME'
                  )
                "
              >
                {{ count('incoming_messages_count') }}
              </button>
            </template>
            <template #outgoing>
              <button
                type="button"
                class="inline p-0 m-0 align-baseline text-[length:inherit] leading-[inherit] font-semibold underline decoration-dotted underline-offset-4 hover:text-n-brand"
                @click="
                  open(
                    'outgoing_messages_count',
                    'REPORT.METRICS.OUTGOING_MESSAGES.NAME'
                  )
                "
              >
                {{ count('outgoing_messages_count') }}
              </button>
            </template>
          </I18nT>
        </span>
      </li>
      <li v-if="hasFirstResponse" class="flex gap-3">
        <span class="i-lucide-timer size-5 mt-1 shrink-0 text-n-brand" />
        <span class="min-w-0">
          <I18nT keypath="REPORT.PLAIN_SUMMARY.FIRST_RESPONSE" tag="span">
            <template #avg>
              <button
                type="button"
                class="inline p-0 m-0 align-baseline text-[length:inherit] leading-[inherit] font-semibold underline decoration-dotted underline-offset-4 hover:text-n-brand"
                @click="
                  open(
                    'avg_first_response_time',
                    'REPORT.METRICS.FIRST_RESPONSE_TIME.NAME'
                  )
                "
              >
                {{ time('avg_first_response_time') }}
              </button>
            </template>
            <template #half>
              <strong>{{ time('p50_first_response_time') }}</strong>
            </template>
            <template #most>
              <strong>{{ time('p90_first_response_time') }}</strong>
            </template>
          </I18nT>
        </span>
      </li>
      <li v-if="hasResolutions" class="flex gap-3">
        <span class="i-lucide-circle-check size-5 mt-1 shrink-0 text-n-brand" />
        <span class="min-w-0">
          <I18nT keypath="REPORT.PLAIN_SUMMARY.RESOLUTION" tag="span">
            <template #resolved>
              <button
                type="button"
                class="inline p-0 m-0 align-baseline text-[length:inherit] leading-[inherit] font-semibold underline decoration-dotted underline-offset-4 hover:text-n-brand"
                @click="
                  open(
                    'resolutions_count',
                    'REPORT.METRICS.RESOLUTION_COUNT.NAME'
                  )
                "
              >
                {{
                  t('REPORT.PLAIN_SUMMARY.RESOLVED', {
                    count: count('resolutions_count'),
                  })
                }}
              </button>
            </template>
            <template #time>
              <strong>{{ time('avg_resolution_time') }}</strong>
            </template>
          </I18nT>
        </span>
      </li>
    </ul>
    <ReportDrilldownPanel
      v-if="drilldown && drilldownFilters"
      :metric="drilldown"
      :filters="drilldownFilters"
      @close="drilldown = null"
    />
  </section>
</template>
