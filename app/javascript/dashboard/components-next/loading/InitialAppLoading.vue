<script setup>
defineProps({
  message: {
    type: String,
    default: 'Loading your workspace...',
  },
});
</script>

<template>
  <div
    class="flex flex-col items-center justify-center h-screen w-full bg-n-background gap-4"
  >
    <img src="/brand-assets/logo.svg" alt="Logo" class="size-12 mb-2" />
    <div class="w-48 h-1 bg-n-slate-3 rounded-full overflow-hidden">
      <div
        class="h-full bg-n-brand rounded-full animate-[loader-pulse_1.5s_ease-in-out_infinite]"
      />
    </div>
    <span class="text-sm text-n-slate-10">
      {{ message }}
    </span>
  </div>
</template>
