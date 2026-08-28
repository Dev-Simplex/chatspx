<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';

import { useCaptainAssistantModel } from 'dashboard/composables/useCaptainAssistantModel';

import AiSegmented from 'dashboard/components-next/agents-ui/AiSegmented.vue';
import AgentFlowSimple from 'dashboard/components-next/agents/workflow/AgentFlowSimple.vue';
import AgentFlowGraph from 'dashboard/components-next/agents/workflow/AgentFlowGraph.vue';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const assistantId = computed(() => Number(route.params.assistantId));
const agent = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

const { assistantModel } = useCaptainAssistantModel();

const view = ref('simple');
const OPTIONS = computed(() => [
  { value: 'simple', label: t('CAPTAIN.AGENT_TABS.FLOW.VIEW_SIMPLE') },
  { value: 'tech', label: t('CAPTAIN.AGENT_TABS.FLOW.VIEW_TECH') },
]);

onMounted(() => {
  if (!agent.value) store.dispatch('captainAssistants/get').catch(() => {});
});
</script>

<template>
  <div class="px-6 pt-4 pb-10 mx-auto space-y-4 max-w-3xl">
    <div class="flex flex-wrap gap-3 items-center">
      <AiSegmented v-model="view" :options="OPTIONS" />
      <span class="text-[12px] text-n-slate-10">{{
        t('CAPTAIN.AGENT_TABS.FLOW.HINT')
      }}</span>
    </div>
    <AgentFlowSimple
      v-if="view === 'simple'"
      :assistant="agent || {}"
      :model="assistantModel || ''"
    />
    <AgentFlowGraph
      v-else
      :assistant="agent || {}"
      :model="assistantModel || ''"
    />
  </div>
</template>
