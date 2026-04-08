<script setup>
import { ref, computed } from 'vue';
import AgentWorkflow from '../workflow/AgentWorkflow.vue';
import DebounceConfig from './DebounceConfig.vue';
import RouterConfig from './RouterConfig.vue';
import BusinessHoursConfig from './BusinessHoursConfig.vue';
import MediaPipelineConfig from './MediaPipelineConfig.vue';
import HumanizerConfig from './HumanizerConfig.vue';
import CopilotTriggerConfig from './CopilotTriggerConfig.vue';
import DedupConfig from './DedupConfig.vue';

const props = defineProps({
  assistant: { type: Object, required: true },
});

const emit = defineEmits(['save']);

const behavior = ref({ ...(props.assistant.behavior || {}) });

const assistantWithBehavior = computed(() => ({
  ...props.assistant,
  behavior: behavior.value,
}));

function updateBehavior(key, value) {
  behavior.value = { ...behavior.value, [key]: value };
}

function scrollToBehavior(key) {
  const el = document.getElementById(`behavior-${key}`);
  if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function save() {
  emit('save', behavior.value);
}
</script>

<template>
  <div class="flex flex-col gap-4">
    <AgentWorkflow
      :assistant="assistantWithBehavior"
      @scroll-to-behavior="scrollToBehavior"
    />

    <div class="space-y-4">
      <RouterConfig
        :model-value="behavior.router"
        @update:model-value="updateBehavior('router', $event)"
      />

      <BusinessHoursConfig
        :model-value="behavior.business_hours"
        @update:model-value="updateBehavior('business_hours', $event)"
      />

      <DebounceConfig
        :model-value="behavior.debounce_seconds"
        @update:model-value="updateBehavior('debounce_seconds', $event)"
      />

      <MediaPipelineConfig
        :model-value="behavior.media_pipeline"
        @update:model-value="updateBehavior('media_pipeline', $event)"
      />

      <HumanizerConfig
        :model-value="behavior.humanizer"
        @update:model-value="updateBehavior('humanizer', $event)"
      />

      <DedupConfig
        :model-value="behavior.dedup"
        @update:model-value="updateBehavior('dedup', $event)"
      />

      <CopilotTriggerConfig
        :model-value="behavior.copilot_trigger"
        @update:model-value="updateBehavior('copilot_trigger', $event)"
      />
    </div>

    <div class="flex justify-end">
      <button
        class="rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700"
        @click="save"
      >
        {{ $t('CAPTAIN.BEHAVIOR.SAVE') }}
      </button>
    </div>
  </div>
</template>
