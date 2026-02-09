<script setup>
import BackButton from 'dashboard/components/widgets/BackButton.vue';
import ReportsSurface from './ReportsSurface.vue';

defineProps({
  headerTitle: {
    required: true,
    type: String,
  },
  headerDescription: {
    type: String,
    default: '',
  },
  hasBackButton: {
    type: Boolean,
    default: false,
  },
});
</script>

<template>
  <section class="pt-8 pb-6">
    <ReportsSurface variant="raised" padding="lg">
      <div v-if="hasBackButton" class="mb-4">
        <BackButton compact />
      </div>
      <div class="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div class="flex flex-col gap-2 max-w-3xl">
          <span
            class="text-3xl md:text-4xl font-semibold tracking-tight text-n-slate-12"
          >
            {{ headerTitle }}
          </span>
          <div v-if="$slots.meta" class="flex items-center gap-2">
            <slot name="meta" />
          </div>
          <p v-if="headerDescription" class="text-sm text-n-slate-11">
            {{ headerDescription }}
          </p>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <slot />
        </div>
      </div>
      <div
        class="mt-5 h-px bg-gradient-to-r from-n-brand/40 via-n-container/40 to-transparent"
      />
    </ReportsSurface>
  </section>
</template>
