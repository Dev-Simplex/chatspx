<script setup>
defineProps({
  message: {
    type: Object,
    required: true,
  },
});
</script>

<template>
  <div class="flex justify-end">
    <div
      class="bg-n-brand/10 text-n-slate-12 rounded-lg px-3 py-2 text-sm max-w-[80%] break-words"
    >
      {{ message.content }}
    </div>
  </div>
</template>
