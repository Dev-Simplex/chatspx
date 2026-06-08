<script setup>
import { computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useClipboard } from '@vueuse/core';
import AgentWorkflow from '../workflow/AgentWorkflow.vue';
import StatsCard from '../StatsCard.vue';
import activityAnim from 'dashboard/assets/lottie/useanimations/activity.json';
import archiveAnim from 'dashboard/assets/lottie/useanimations/archive.json';
import downloadAnim from 'dashboard/assets/lottie/useanimations/download.json';
import exploreAnim from 'dashboard/assets/lottie/useanimations/explore.json';

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const { copy, copied } = useClipboard({ copiedDuring: 2000 });
const { copy: copyTpl, copied: copiedTemplate } = useClipboard({
  copiedDuring: 2000,
});

const assistantId = computed(() => Number(route.params.assistantId));

const agent = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

const responses = computed(() => store.getters['captainResponses/getRecords']);
const documents = computed(() => store.getters['captainDocuments/getRecords']);
const inboxes = computed(() => store.getters['captainInboxes/getRecords']);
const scenarios = computed(() => store.getters['captainScenarios/getRecords']);

onMounted(() => {
  const params = { assistantId: assistantId.value };
  store.dispatch('captainResponses/get', params);
  store.dispatch('captainDocuments/get', params);
  store.dispatch('captainInboxes/get', params);
  store.dispatch('captainScenarios/get', params);
});

const hasBehavior = computed(() => {
  const b = agent.value?.behavior;
  return b && Object.keys(b).length > 0;
});

const enabledBehaviors = computed(() => {
  const b = agent.value?.behavior || {};
  return Object.keys(b).filter(k => {
    const v = b[k];
    if (typeof v === 'object' && v !== null) return v.enabled !== false;
    if (typeof v === 'number') return v > 0;
    return Boolean(v);
  });
});

const formattedBehavior = computed(() =>
  agent.value?.behavior ? JSON.stringify(agent.value.behavior, null, 2) : ''
);

const formattedConfig = computed(() =>
  agent.value?.config ? JSON.stringify(agent.value.config, null, 2) : ''
);

const behaviorTemplate = JSON.stringify(
  {
    debounce_seconds: 15,
    router: {
      enabled: true,
      skip_labels: [],
      skip_groups: false,
      skip_agent_bot: true,
      skip_activity: false,
    },
    business_hours: { enabled: false },
    media_pipeline: {
      enabled: false,
      audio_transcription: false,
      image_description: false,
    },
    humanizer: { enabled: false, max_chars: 300, delay_ms: 500 },
    dedup: { enabled: false, ttl_seconds: 60 },
    copilot_trigger: { enabled: false, hashtag: '#copilot' },
  },
  null,
  2
);

function copyBehavior() {
  copy(formattedBehavior.value);
}

function copyConfig() {
  copy(formattedConfig.value);
}

function copyTemplate() {
  copyTpl(behaviorTemplate);
}

const stats = computed(() => [
  {
    animation: activityAnim,
    mode: 'hover',
    fallback: 'i-lucide-message-square',
    value: responses.value.length,
    sublabel: t('CAPTAIN.AGENT_TABS.OVERVIEW.RESPONSES'),
  },
  {
    animation: archiveAnim,
    mode: 'hover',
    fallback: 'i-lucide-file-text',
    value: documents.value.length,
    sublabel: t('CAPTAIN.AGENT_TABS.OVERVIEW.DOCUMENTS'),
  },
  {
    animation: downloadAnim,
    mode: 'hover',
    fallback: 'i-lucide-inbox',
    value: inboxes.value.length,
    sublabel: t('CAPTAIN.AGENT_TABS.OVERVIEW.INBOXES'),
  },
  {
    animation: exploreAnim,
    mode: 'hover',
    fallback: 'i-lucide-crosshair',
    value: scenarios.value.length,
    sublabel: t('CAPTAIN.AGENT_TABS.OVERVIEW.SCENARIOS_LABEL'),
  },
]);
</script>

<template>
  <div class="space-y-6 p-6">
    <!-- Workflow visual (só se tem behavior) -->
    <AgentWorkflow v-if="hasBehavior" :assistant="agent" />

    <!-- Stats grid -->
    <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <StatsCard
        v-for="stat in stats"
        :key="stat.fallback"
        :animation-data="stat.animation"
        :fallback-icon="stat.fallback"
        :value="stat.value"
        :label="stat.sublabel"
        :icon-mode="stat.mode"
      />
    </div>

    <!-- Agent Config Card (quando tem behavior) -->
    <template v-if="hasBehavior">
      <div
        class="overflow-hidden rounded-xl border border-n-weak bg-white dark:bg-n-solid-2"
      >
        <div class="border-b border-n-weak px-5 py-4">
          <h3 class="text-sm font-semibold text-n-slate-12">
            {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.AGENT_CONFIG') }}
          </h3>
        </div>
        <dl class="divide-y divide-n-weak">
          <!-- Modelo -->
          <div class="flex items-start gap-4 px-5 py-3">
            <dt
              class="flex w-28 shrink-0 items-center gap-1.5 text-xs text-n-slate-10"
            >
              <i class="i-lucide-cpu size-3.5" />
              {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.MODEL') }}
            </dt>
            <dd class="font-mono text-sm text-n-slate-12">
              {{ agent.config?.model || '—' }}
            </dd>
          </div>
          <!-- Temperatura -->
          <div class="flex items-start gap-4 px-5 py-3">
            <dt
              class="flex w-28 shrink-0 items-center gap-1.5 text-xs text-n-slate-10"
            >
              <i class="i-lucide-thermometer size-3.5" />
              {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.TEMPERATURE') }}
            </dt>
            <dd class="font-mono text-sm text-n-slate-12">
              {{ agent.config?.temperature ?? '—' }}
            </dd>
          </div>
          <!-- Produto -->
          <div class="flex items-center gap-4 px-5 py-3">
            <dt
              class="flex w-28 shrink-0 items-center gap-1.5 text-xs text-n-slate-10"
            >
              <i class="i-lucide-package size-3.5" />
              {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.PRODUCT') }}
            </dt>
            <dd class="text-sm text-n-slate-12">
              {{ agent.config?.product_name || '—' }}
            </dd>
          </div>
          <!-- Behaviors habilitados -->
          <div class="flex items-start gap-4 px-5 py-3">
            <dt
              class="flex w-28 shrink-0 items-center gap-1.5 text-xs text-n-slate-10"
            >
              <i class="i-lucide-settings size-3.5" />
              {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.BEHAVIORS') }}
            </dt>
            <dd class="flex flex-wrap gap-1.5">
              <span
                v-for="bkey in enabledBehaviors"
                :key="bkey"
                class="rounded-full bg-n-alpha-2 px-2 py-0.5 font-mono text-xs text-n-slate-11"
              >
                {{ bkey }}
              </span>
              <span
                v-if="!enabledBehaviors.length"
                class="text-xs text-n-slate-10"
              >
                {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.NONE_CONFIGURED') }}
              </span>
            </dd>
          </div>
        </dl>
      </div>

      <!-- Behavior JSON -->
      <div
        v-if="formattedBehavior"
        class="overflow-hidden rounded-xl border border-n-weak"
      >
        <div
          class="flex items-center justify-between border-b border-n-weak bg-n-alpha-1 px-4 py-2"
        >
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.BEHAVIOR_JSON') }}
          </span>
          <button
            type="button"
            class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-n-slate-10 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12"
            @click="copyBehavior"
          >
            <i
              :class="
                copied
                  ? 'i-lucide-check size-3 text-green-600'
                  : 'i-lucide-clipboard size-3'
              "
            />
            {{
              copied
                ? t('CAPTAIN.AGENT_TABS.OVERVIEW.COPIED')
                : t('CAPTAIN.AGENT_TABS.OVERVIEW.COPY')
            }}
          </button>
        </div>
        <div class="max-h-64 overflow-auto bg-slate-950 p-3">
          <pre class="whitespace-pre-wrap font-mono text-xs text-slate-300">{{
            formattedBehavior
          }}</pre>
        </div>
      </div>
    </template>

    <!-- Getting Started (sem behavior) -->
    <template v-else>
      <div
        class="rounded-xl border border-dashed border-n-weak bg-n-alpha-1 p-8"
      >
        <div class="mx-auto max-w-lg text-center">
          <i class="i-lucide-rocket mx-auto mb-4 size-10 text-n-slate-9" />
          <h3 class="mb-2 text-base font-semibold text-n-slate-12">
            {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.CONFIGURE_TITLE') }}
          </h3>
          <p class="mb-6 text-sm text-n-slate-10">
            {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.CONFIGURE_DESCRIPTION') }}
          </p>

          <!-- JSON Template copiável -->
          <div
            class="overflow-hidden rounded-lg border border-n-weak text-left"
          >
            <div
              class="flex items-center justify-between border-b border-n-weak bg-n-alpha-1 px-3 py-2"
            >
              <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
              <span class="font-mono text-xs text-n-slate-10">
                behavior.json
              </span>
              <button
                type="button"
                class="flex items-center gap-1 text-xs text-n-slate-10 transition-colors hover:text-n-slate-12"
                @click="copyTemplate"
              >
                <i
                  :class="
                    copiedTemplate
                      ? 'i-lucide-check size-3 text-green-600'
                      : 'i-lucide-clipboard size-3'
                  "
                />
                {{
                  copiedTemplate
                    ? t('CAPTAIN.AGENT_TABS.OVERVIEW.COPIED')
                    : t('CAPTAIN.AGENT_TABS.OVERVIEW.COPY')
                }}
              </button>
            </div>
            <div class="max-h-48 overflow-x-auto bg-slate-950 p-3">
              <pre class="font-mono text-xs text-slate-300">{{
                behaviorTemplate
              }}</pre>
            </div>
          </div>
        </div>
      </div>
    </template>

    <!-- Config JSON (sempre mostra) -->
    <div
      v-if="formattedConfig"
      class="overflow-hidden rounded-xl border border-n-weak"
    >
      <div
        class="flex items-center justify-between border-b border-n-weak bg-n-alpha-1 px-4 py-2"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.CONFIG_JSON') }}
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-n-slate-10 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12"
          @click="copyConfig"
        >
          <i
            :class="
              copied
                ? 'i-lucide-check size-3 text-green-600'
                : 'i-lucide-clipboard size-3'
            "
          />
          {{
            copied
              ? t('CAPTAIN.AGENT_TABS.OVERVIEW.COPIED')
              : t('CAPTAIN.AGENT_TABS.OVERVIEW.COPY')
          }}
        </button>
      </div>
      <div class="max-h-64 overflow-auto bg-slate-950 p-3">
        <pre class="whitespace-pre-wrap font-mono text-xs text-slate-300">{{
          formattedConfig
        }}</pre>
      </div>
    </div>
  </div>
</template>
