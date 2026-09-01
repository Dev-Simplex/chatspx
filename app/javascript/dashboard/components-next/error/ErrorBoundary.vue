<script setup>
import { ref, onErrorCaptured } from 'vue';
import { useI18n } from 'vue-i18n';

defineProps({
  fallbackTitle: { type: String, default: '' },
});

const { t } = useI18n();
const error = ref(null);
const retryKey = ref(0);

onErrorCaptured(err => {
  // eslint-disable-next-line no-console
  console.error('[ErrorBoundary]', err);
  error.value = err;
  return false;
});

const retry = () => {
  error.value = null;
  retryKey.value += 1;
};
</script>

<template>
  <div
    v-if="error"
    class="px-6 py-10 text-center bg-n-solid-1 dark:bg-n-solid-2 rounded-lg"
    role="alert"
  >
    <p class="text-sm text-n-slate-11 mb-4">
      {{ fallbackTitle || t('GENERIC.ERROR_BOUNDARY.MESSAGE') }}
    </p>
    <button
      type="button"
      class="px-4 py-2 text-sm rounded-md bg-n-brand text-white hover:bg-n-teal-10 transition"
      @click="retry"
    >
      {{ t('GENERIC.ERROR_BOUNDARY.RETRY') }}
    </button>
  </div>
  <slot v-else :key="retryKey" />
</template>
