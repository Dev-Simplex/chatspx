<script setup>
import { computed } from 'vue';

const props = defineProps({
  modelValue: { type: [Number, String], default: 0 },
});

const emit = defineEmits(['update:modelValue']);

const seconds = computed({
  get: () => Number(props.modelValue) || 0,
  set: val => emit('update:modelValue', Number(val)),
});

const enabled = computed({
  get: () => seconds.value > 0,
  set: val => {
    if (!val) emit('update:modelValue', 0);
    else if (seconds.value === 0) emit('update:modelValue', 15);
  },
});
</script>

<template>
  <div
    id="behavior-debounce_seconds"
    class="rounded-lg border border-n-weak p-4 dark:bg-n-solid-2"
  >
    <div class="flex items-center justify-between">
      <div>
        <h4 class="text-sm font-semibold text-n-slate-12">
          {{ $t('CAPTAIN.BEHAVIOR.DEBOUNCE.TITLE') }}
        </h4>
        <p class="text-xs text-n-slate-10">
          {{ $t('CAPTAIN.BEHAVIOR.DEBOUNCE.DESCRIPTION') }}
        </p>
      </div>
      <input v-model="enabled" type="checkbox" class="toggle-checkbox" />
    </div>
    <div v-if="enabled" class="mt-3">
      <label class="mb-1 block text-xs text-n-slate-10">
        {{ $t('CAPTAIN.BEHAVIOR.DEBOUNCE.SECONDS_LABEL') }}
      </label>
      <input
        v-model.number="seconds"
        type="number"
        min="1"
        max="60"
        class="w-24 rounded border border-n-weak bg-white px-2 py-1 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
      />
    </div>
  </div>
</template>
