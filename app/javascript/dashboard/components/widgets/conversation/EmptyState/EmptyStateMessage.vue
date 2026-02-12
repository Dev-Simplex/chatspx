<script>
import FeaturePlaceholder from './FeaturePlaceholder.vue';

export default {
  components: { FeaturePlaceholder },
  props: {
    message: {
      type: String,
      required: true,
    },
    title: {
      type: String,
      default: '',
    },
  },
};
</script>

<template>
  <div class="empty-state-message flex flex-col items-center justify-center h-full px-6 py-8">
    <div class="empty-state-message__illustration mb-4 flex items-center justify-center rounded-2xl bg-n-slate-2 dark:bg-n-slate-3 p-6">
      <img
        class="w-24 h-24 sm:w-32 sm:h-32 hidden dark:block object-contain"
        src="dashboard/assets/images/no-chat-dark.svg"
        alt=""
      />
      <img
        class="w-24 h-24 sm:w-32 sm:h-32 block dark:hidden object-contain"
        src="dashboard/assets/images/no-chat.svg"
        alt=""
      />
    </div>
    <h3
      v-if="title"
      class="empty-state-message__title text-base font-semibold text-n-slate-12 text-center mb-2"
    >
      {{ title }}
    </h3>
    <p class="empty-state-message__text text-sm text-n-slate-11 font-normal text-center max-w-sm">
      {{ message }}
    </p>
    <!-- Cmd bar, keyboard shortcuts placeholder -->
    <FeaturePlaceholder />
  </div>
</template>
