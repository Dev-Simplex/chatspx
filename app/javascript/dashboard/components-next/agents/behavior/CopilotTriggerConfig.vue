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
      hashtag: config.value.hashtag || '#copilot',
    }),
});

function updateField(key, value) {
  emit('update:modelValue', { ...config.value, [key]: value });
}
</script>

<template>
  <div
    id="behavior-copilot_trigger"
    class="rounded-lg border border-n-weak p-4 dark:bg-n-solid-2"
  >
    <div class="flex items-center justify-between">
      <div>
        <h4 class="text-sm font-semibold text-n-slate-12">
          {{ $t('CAPTAIN.BEHAVIOR.COPILOT_TRIGGER.TITLE') }}
        </h4>
        <p class="text-xs text-n-slate-10">
          {{ $t('CAPTAIN.BEHAVIOR.COPILOT_TRIGGER.DESCRIPTION') }}
        </p>
      </div>
      <input v-model="enabled" type="checkbox" class="toggle-checkbox" />
    </div>

    <div v-if="enabled" class="mt-3">
      <label class="mb-1 block text-xs text-n-slate-10">
        {{ $t('CAPTAIN.BEHAVIOR.COPILOT_TRIGGER.HASHTAG_LABEL') }}
      </label>
      <input
        :value="config.hashtag || '#copilot'"
        type="text"
        class="w-40 rounded border border-n-weak bg-white px-2 py-1 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
        @change="updateField('hashtag', $event.target.value)"
      />
    </div>
  </div>
</template>
