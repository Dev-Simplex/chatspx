<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import BehaviorTab from 'dashboard/components-next/agents/behavior/BehaviorTab.vue';

const store = useStore();
const route = useRoute();

const assistantId = computed(() => route.params.assistantId);
const assistant = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

async function saveBehavior(behavior) {
  try {
    await store.dispatch('captainAssistants/update', {
      id: assistantId.value,
      behavior,
    });
    useAlert('Behavior saved successfully');
  } catch {
    useAlert('Failed to save behavior', 'error');
  }
}
</script>

<template>
  <div class="p-4">
    <BehaviorTab v-if="assistant" :assistant="assistant" @save="saveBehavior" />
  </div>
</template>
