<script setup>
defineProps({
  bubble: { type: Boolean, default: false },
});
</script>

<template>
  <div
    class="inline-flex items-center gap-1"
    :class="{
      'px-4 py-2.5 rounded-2xl bg-n-slate-3 dark:bg-n-solid-3': bubble,
    }"
  >
    <span class="size-2 rounded-full bg-n-slate-8 animate-typing-bounce" />
    <span
      class="size-2 rounded-full bg-n-slate-8 animate-typing-bounce [animation-delay:0.15s]"
    />
    <span
      class="size-2 rounded-full bg-n-slate-8 animate-typing-bounce [animation-delay:0.3s]"
    />
  </div>
</template>
