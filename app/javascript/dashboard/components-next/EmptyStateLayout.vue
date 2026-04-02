<script setup>
import Policy from 'dashboard/components/policy.vue';

defineProps({
  title: {
    type: String,
    required: true,
  },
  subtitle: {
    type: String,
    required: true,
  },
  actionPerms: {
    type: Array,
    default: () => [],
  },
  showBackdrop: {
    type: Boolean,
    default: true,
  },
});
</script>

<template>
  <section
    class="relative flex flex-col items-center justify-center w-full h-full overflow-hidden"
  >
    <div
      class="relative w-full max-w-5xl mx-auto overflow-hidden h-full max-h-[28rem]"
    >
      <div
        v-if="showBackdrop"
        class="w-full h-full space-y-4 overflow-y-hidden opacity-50 pointer-events-none"
      >
        <slot name="empty-state-item" />
      </div>
      <div
        class="flex flex-col items-center justify-end w-full h-full pb-20"
        :class="{
          'absolute inset-x-0 bottom-0 bg-gradient-to-t from-n-surface-1 from-25% to-transparent':
            showBackdrop,
        }"
      >
        <div
          class="flex flex-col items-center justify-center gap-6 py-16 px-8 text-center"
          :class="{
            'mt-48': !showBackdrop,
          }"
        >
          <slot name="icon" />
          <div class="flex flex-col items-center justify-center gap-2">
            <h2 class="text-lg font-semibold text-center text-n-slate-12">
              {{ title }}
            </h2>
            <p
              v-if="subtitle"
              class="max-w-sm text-sm text-center text-n-slate-10"
            >
              {{ subtitle }}
            </p>
          </div>
          <Policy :permissions="actionPerms">
            <slot name="actions" />
          </Policy>
        </div>
      </div>
    </div>
  </section>
</template>
