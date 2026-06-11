<script setup>
import { computed } from 'vue';

const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue']);

const config = computed(() => props.modelValue || {});

function updateField(key, value) {
  emit('update:modelValue', { ...config.value, [key]: value });
}
</script>

<template>
  <div
    id="behavior-media_pipeline"
    class="rounded-lg border border-n-weak p-4 dark:bg-n-solid-2"
  >
    <h4 class="text-sm font-semibold text-n-slate-12">
      {{ $t('CAPTAIN.BEHAVIOR.MEDIA_PIPELINE.TITLE') }}
    </h4>
    <p class="mb-3 text-xs text-n-slate-10">
      {{ $t('CAPTAIN.BEHAVIOR.MEDIA_PIPELINE.DESCRIPTION') }}
    </p>

    <div class="space-y-2">
      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <input
          :checked="config.audio_transcription"
          type="checkbox"
          @change="updateField('audio_transcription', $event.target.checked)"
        />
        {{ $t('CAPTAIN.BEHAVIOR.MEDIA_PIPELINE.AUDIO_TRANSCRIPTION') }}
      </label>

      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <input
          :checked="config.image_description"
          type="checkbox"
          @change="updateField('image_description', $event.target.checked)"
        />
        {{ $t('CAPTAIN.BEHAVIOR.MEDIA_PIPELINE.IMAGE_DESCRIPTION') }}
      </label>
    </div>
  </div>
</template>
