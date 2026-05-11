<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import SectionLayout from './SectionLayout.vue';

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const value = computed(
  () => uiSettings.value?.conversation_density || 'comfortable'
);

const options = computed(() => [
  {
    value: 'compact',
    label: t('GENERAL_SETTINGS.FORM.DENSITY.OPTIONS.COMPACT'),
  },
  {
    value: 'comfortable',
    label: t('GENERAL_SETTINGS.FORM.DENSITY.OPTIONS.COMFORTABLE'),
  },
  {
    value: 'spacious',
    label: t('GENERAL_SETTINGS.FORM.DENSITY.OPTIONS.SPACIOUS'),
  },
]);

const setDensity = next => {
  if (next === value.value) return;
  updateUISettings({ conversation_density: next });
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.DENSITY.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.DENSITY.NOTE')"
    with-border
  >
    <div class="flex gap-2 flex-wrap">
      <button
        v-for="opt in options"
        :key="opt.value"
        type="button"
        class="px-3 py-1.5 text-sm rounded-md border transition-colors"
        :class="
          value === opt.value
            ? 'bg-n-brand text-white border-n-brand'
            : 'bg-n-alpha-2 text-n-slate-12 border-n-weak hover:bg-n-alpha-3'
        "
        @click="setDensity(opt.value)"
      >
        {{ opt.label }}
      </button>
    </div>
  </SectionLayout>
</template>
