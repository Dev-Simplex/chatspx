<script setup>
import BackButton from 'dashboard/components/widgets/BackButton.vue';
import ReportsSurface from './ReportsSurface.vue';

defineProps({
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
  hasBackButton: {
    type: Boolean,
    default: false,
  },
  eyebrow: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <section class="pb-6">
    <ReportsSurface variant="raised" padding="lg">
      <div v-if="hasBackButton" class="mb-4">
        <BackButton compact />
      </div>
      <div class="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div class="flex flex-col gap-2 max-w-3xl">
          <span
            v-if="eyebrow"
            class="text-[11px] uppercase tracking-[0.32em] text-n-slate-10"
          >
            {{ eyebrow }}
          </span>
          <span
            class="text-3xl md:text-4xl font-semibold tracking-tight text-n-slate-12"
          >
            {{ title }}
          </span>
          <div v-if="$slots.meta" class="flex items-center gap-2">
            <slot name="meta" />
          </div>
          <p v-if="description" class="text-sm text-n-slate-11">
            {{ description }}
          </p>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <slot name="actions" />
        </div>
      </div>
      <div
        class="mt-5 h-px bg-gradient-to-r from-n-brand/40 via-n-container/40 to-transparent"
      />
    </ReportsSurface>
  </section>
</template>
