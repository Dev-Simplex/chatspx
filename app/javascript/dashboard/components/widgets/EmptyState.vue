<script>
export default {
  props: {
    title: { type: String, default: '' },
    message: { type: String, default: '' },
  },
};
</script>

<template>
  <div class="flex flex-col items-center justify-center py-16 px-8 text-center">
    <slot name="icon" />
    <h3 v-if="title" class="text-lg font-semibold text-n-slate-12 mb-2">
      {{ title }}
    </h3>
    <p v-if="message" class="text-sm text-n-slate-10 max-w-sm mb-6">
      {{ message }}
    </p>
    <slot />
  </div>
</template>
