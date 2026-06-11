<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';

const props = defineProps({
  signals: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();
const { summaryFor, pillFor } = useReportNarrative();

const narrative = computed(() => summaryFor(props.signals));
const hasSignals = computed(() => (props.signals || []).length > 0);

const ICONS = { highlight: '🏆', attention: '⚠️', allGood: '👍' };
</script>

<template>
  <section
    v-if="hasSignals"
    class="rounded-2xl border border-n-container/60 bg-n-solid-2/90 px-6 py-5 shadow-sm mt-4"
  >
    <span class="text-xs uppercase tracking-[0.2em] text-n-slate-10">
      {{ t('REPORT.NARRATIVE.EYEBROW') }}
    </span>
    <div class="mt-4 grid gap-4 grid-cols-1 sm:grid-cols-2">
      <div
        v-if="narrative.highlight"
        class="rounded-2xl border border-n-teal-6 bg-n-teal-2/60 p-4"
      >
        <div class="flex items-center gap-2">
          <span class="text-lg">{{ ICONS.highlight }}</span>
          <p class="text-sm font-semibold text-n-slate-12">
            {{ t('REPORT.NARRATIVE.HIGHLIGHT_TITLE') }}
          </p>
        </div>
        <p class="mt-2 text-sm font-medium text-n-slate-12">
          {{ narrative.highlight.label }}
        </p>
        <p class="mt-1 text-xs text-n-slate-11">
          {{ narrative.highlight.phrase }}
        </p>
      </div>

      <div
        v-if="narrative.attention"
        class="rounded-2xl border border-n-amber-6 bg-n-amber-2/60 p-4"
      >
        <div class="flex items-center gap-2">
          <span class="text-lg">{{ ICONS.attention }}</span>
          <p class="text-sm font-semibold text-n-slate-12">
            {{ t('REPORT.NARRATIVE.ATTENTION_TITLE') }}
          </p>
          <span
            v-if="pillFor(narrative.attention.signal)"
            class="text-[11px] flex items-center gap-1 px-2 py-0.5 rounded-full border font-medium"
            :class="pillFor(narrative.attention.signal).colorClass"
          >
            <span>{{ pillFor(narrative.attention.signal).icon }}</span>
            <span>{{ pillFor(narrative.attention.signal).label }}</span>
          </span>
        </div>
        <p class="mt-2 text-sm font-medium text-n-slate-12">
          {{ narrative.attention.label }}
        </p>
        <p class="mt-1 text-xs text-n-slate-11">
          {{ narrative.attention.phrase }}
        </p>
      </div>

      <div
        v-else-if="narrative.allGood"
        class="rounded-2xl border border-n-teal-6 bg-n-teal-2/60 p-4 flex items-center gap-2"
      >
        <span class="text-lg">{{ ICONS.allGood }}</span>
        <p class="text-sm font-medium text-n-slate-12">
          {{ t('REPORT.NARRATIVE.ALL_GOOD') }}
        </p>
      </div>
    </div>
  </section>
</template>
