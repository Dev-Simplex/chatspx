<script setup>
import { ref } from 'vue';

const props = defineProps({
  label: { type: String, required: true },
  action: { type: Function, required: true },
});

const executed = ref(false);
const executing = ref(false);

async function handleClick() {
  if (executed.value || executing.value) return;
  executing.value = true;
  try {
    await props.action();
    executed.value = true;
  } finally {
    executing.value = false;
  }
}
</script>

<template>
  <button
    class="mt-1 inline-flex items-center gap-1 rounded border px-2 py-0.5 text-xs font-medium transition-colors"
    :class="
      executed
        ? 'border-green-300 bg-green-50 text-green-700'
        : 'border-primary-300 bg-primary-25 text-primary-700 hover:bg-primary-50'
    "
    :disabled="executed || executing"
    @click="handleClick"
  >
    <span
      v-if="executing"
      class="inline-block h-3 w-3 animate-spin rounded-full border-2 border-primary-300 border-t-transparent"
    />
    <span v-else-if="executed">&#10003;</span>
    {{ executed ? 'Done' : label }}
  </button>
</template>
