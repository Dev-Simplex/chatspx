<script setup>
import Spinner from 'shared/components/Spinner.vue';
import ReportsSurface from '../ReportsSurface.vue';

defineProps({
  header: {
    type: String,
    default: '',
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  loadingMessage: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <ReportsSurface
    variant="base"
    padding="lg"
    class="flex flex-col flex-grow text-n-slate-12 min-h-[11rem]"
  >
    <div
      class="card-header grid w-full mb-6 grid-cols-[repeat(auto-fit,minmax(max-content,50%))] gap-y-3"
    >
      <slot name="header">
        <div class="flex items-center gap-2 flex-row">
          <h5 class="mb-0 text-n-slate-12 font-semibold text-lg">
            {{ header }}
          </h5>
          <span
            class="flex flex-row items-center py-0.5 px-2 rounded-full bg-n-teal-3 text-xs"
          >
            <span
              class="bg-n-teal-9 h-1 w-1 rounded-full mr-1 rtl:mr-0 rtl:ml-0"
            />
            <span class="text-xs text-n-teal-11">
              {{ $t('OVERVIEW_REPORTS.LIVE') }}
            </span>
          </span>
        </div>
        <div class="flex flex-row items-center justify-end gap-2">
          <slot name="control" />
        </div>
      </slot>
    </div>
    <div
      v-if="!isLoading"
      class="card-body max-w-full w-full ml-auto mr-auto justify-between flex gap-4"
    >
      <slot />
    </div>
    <div
      v-else-if="isLoading"
      class="items-center flex text-base justify-center px-12 py-6"
    >
      <Spinner />
      <span class="text-n-slate-11">
        {{ loadingMessage }}
      </span>
    </div>
  </ReportsSurface>
</template>
