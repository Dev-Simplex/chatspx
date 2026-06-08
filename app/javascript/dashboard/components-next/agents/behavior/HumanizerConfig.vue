<script setup>
import { computed } from 'vue';

const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue']);

const config = computed(() => props.modelValue || {});

const enabled = computed({
  get: () => config.value.enabled === true,
  set: val =>
    emit('update:modelValue', {
      ...config.value,
      enabled: val,
      max_chars: config.value.max_chars || 300,
      delay_ms: config.value.delay_ms || 500,
    }),
});

function updateField(key, value) {
  emit('update:modelValue', { ...config.value, [key]: value });
}
</script>

<template>
  <div
    id="behavior-humanizer"
    class="rounded-lg border border-n-weak p-4 dark:bg-n-solid-2"
  >
    <div class="flex items-center justify-between">
      <div>
        <h4 class="text-sm font-semibold text-n-slate-12">
          {{ $t('CAPTAIN.BEHAVIOR.HUMANIZER.TITLE') }}
        </h4>
        <p class="text-xs text-n-slate-10">
          {{ $t('CAPTAIN.BEHAVIOR.HUMANIZER.DESCRIPTION') }}
        </p>
      </div>
      <input v-model="enabled" type="checkbox" class="toggle-checkbox" />
    </div>

    <div v-if="enabled" class="mt-3 flex gap-4">
      <div>
        <label class="mb-1 block text-xs text-n-slate-10">
          {{ $t('CAPTAIN.BEHAVIOR.HUMANIZER.MAX_CHARS') }}
        </label>
        <input
          :value="config.max_chars || 300"
          type="number"
          min="100"
          max="1000"
          class="w-24 rounded border border-n-weak bg-white px-2 py-1 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          @change="updateField('max_chars', Number($event.target.value))"
        />
      </div>
      <div>
        <label class="mb-1 block text-xs text-n-slate-10">
          {{ $t('CAPTAIN.BEHAVIOR.HUMANIZER.DELAY_MS') }}
        </label>
        <input
          :value="config.delay_ms || 500"
          type="number"
          min="100"
          max="5000"
          step="100"
          class="w-24 rounded border border-n-weak bg-white px-2 py-1 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          @change="updateField('delay_ms', Number($event.target.value))"
        />
      </div>
    </div>
  </div>
</template>
