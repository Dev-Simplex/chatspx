<script setup>
import { onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Avatar from 'next/avatar/Avatar.vue';
import BorderBeam from 'dashboard/components-next/effects/BorderBeam.vue';
import { aiAccent, aiAccentVars } from 'dashboard/helper/aiAccent';

const store = useStore();
const assistants = useMapGetter('captainAssistants/getRecords');
const inboxes = useMapGetter('inboxes/getInboxes');

onMounted(() => {
  store.dispatch('captainAssistants/get');
  // Idempotent — guarantees inbox names resolve even if this page is opened
  // before the app shell has populated the inboxes store.
  store.dispatch('inboxes/get');
});

const inboxNamesFor = assistant =>
  (assistant.inbox_ids || [])
    .map(id => inboxes.value.find(inbox => inbox.id === id)?.name)
    .filter(Boolean);
</script>

<template>
  <section v-if="assistants.length" class="mt-8">
    <div class="flex flex-col gap-1 pb-4 border-b border-n-weak">
      <h2 class="text-heading-2 text-n-slate-12">
        {{ $t('AGENT_MGMT.AI_AGENTS.TITLE') }}
      </h2>
      <p class="text-body-main text-n-slate-11 mb-0">
        {{ $t('AGENT_MGMT.AI_AGENTS.DESCRIPTION') }}
      </p>
    </div>
    <div class="divide-y divide-n-weak">
      <div
        v-for="assistant in assistants"
        :key="assistant.id"
        class="flex justify-between flex-row items-start gap-4 py-4"
      >
        <div class="flex items-center gap-4">
          <Avatar
            :src="assistant.avatar_url"
            :name="assistant.name"
            :accent="aiAccent(assistant.id)"
            :size="40"
            hide-offline-status
          />
          <div class="flex flex-col gap-1.5 items-start">
            <div class="flex items-center gap-2">
              <span class="text-heading-3 text-n-slate-12">
                {{ assistant.name }}
              </span>
              <span
                class="ai-badge relative inline-flex items-center gap-1 overflow-hidden rounded-md px-1.5 py-0.5 text-xs font-medium bg-[var(--ai-bg)] text-[var(--ai-text)] dark:bg-[var(--ai-dark-bg)] dark:text-[var(--ai-dark-text)]"
                :style="aiAccentVars(assistant.id)"
              >
                <BorderBeam
                  :duration="5"
                  :size="1.5"
                  color-from="rgb(var(--violet-8))"
                  color-to="rgb(var(--violet-11))"
                />
                <span class="i-lucide-sparkles size-3" />
                {{ $t('AGENT_MGMT.AI_AGENTS.BADGE') }}
              </span>
            </div>
            <span
              v-if="assistant.description"
              class="text-body-main text-n-slate-11"
            >
              {{ assistant.description }}
            </span>
            <div class="flex items-center gap-1.5 flex-wrap">
              <span class="text-xs text-n-slate-11">
                {{ $t('AGENT_MGMT.AI_AGENTS.INBOXES_LABEL') }}
              </span>
              <template v-if="inboxNamesFor(assistant).length">
                <span
                  v-for="name in inboxNamesFor(assistant)"
                  :key="name"
                  class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-xs text-n-slate-12"
                >
                  {{ name }}
                </span>
              </template>
              <span v-else class="text-xs text-n-slate-10">
                {{ $t('AGENT_MGMT.AI_AGENTS.NO_INBOXES') }}
              </span>
            </div>
          </div>
        </div>
        <!-- read-only por design (D-2): sem botões de editar/deletar; gestão na área Agentes IA -->
      </div>
    </div>
  </section>
</template>
