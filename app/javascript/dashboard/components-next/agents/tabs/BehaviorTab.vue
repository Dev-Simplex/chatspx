<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import BehaviorTabComponent from '../behavior/BehaviorTab.vue';

const route = useRoute();
const store = useStore();

const assistantId = computed(() => Number(route.params.assistantId));

const agent = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

async function onSave(behavior) {
  await store.dispatch('captainAssistants/update', {
    id: assistantId.value,
    behavior,
  });
}
</script>

<template>
  <div class="p-6">
    <BehaviorTabComponent v-if="agent" :assistant="agent" @save="onSave" />
  </div>
</template>
