<script setup>
import { ref, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useClipboard } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { copy, copied } = useClipboard({ copiedDuring: 2000 });

const assistantId = computed(() => Number(route.params.assistantId));
const agent = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

const showDeleteConfirm = ref(false);

const fullConfig = computed(() => {
  if (!agent.value) return '';
  return JSON.stringify(
    {
      name: agent.value.name,
      description: agent.value.description,
      config: agent.value.config,
      behavior: agent.value.behavior,
      guardrails: agent.value.guardrails,
      response_guidelines: agent.value.response_guidelines,
    },
    null,
    2
  );
});

function copyConfig() {
  copy(fullConfig.value);
}

async function deleteAgent() {
  await store.dispatch('captainAssistants/delete', assistantId.value);
  useAlert(t('CAPTAIN.AGENT_TABS.SETTINGS.DELETE_SUCCESS'));
  router.push({ name: 'agents_dashboard' });
}
</script>

<!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
<template>
  <div class="max-w-3xl space-y-6 p-6">
    <!-- Agent Info Card (read-only) -->
    <div
      class="overflow-hidden rounded-xl border border-n-weak bg-white dark:bg-n-solid-2"
    >
      <div
        class="flex items-center justify-between border-b border-n-weak px-5 py-4"
      >
        <h3
          class="flex items-center gap-2 text-sm font-semibold text-n-slate-12"
        >
          <i class="i-lucide-info size-4" />
          {{ t('CAPTAIN.AGENT_TABS.SETTINGS.INFO_TITLE') }}
        </h3>
        <button
          type="button"
          class="flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-n-slate-10 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12"
          @click="copyConfig"
        >
          <i
            :class="
              copied
                ? 'i-lucide-check size-3 text-green-600'
                : 'i-lucide-clipboard size-3'
            "
          />
          {{ copied ? 'Copiado!' : 'Copiar tudo' }}
        </button>
      </div>
      <dl class="divide-y divide-n-weak">
        <div v-if="agent?.name" class="flex items-start gap-4 px-5 py-3">
          <dt class="w-32 shrink-0 text-xs text-n-slate-10">Nome</dt>
          <dd class="text-sm font-medium text-n-slate-12">
            {{ agent.name }}
          </dd>
        </div>
        <div v-if="agent?.description" class="flex items-start gap-4 px-5 py-3">
          <dt class="w-32 shrink-0 text-xs text-n-slate-10">Descricao</dt>
          <dd class="text-sm text-n-slate-12">
            {{ agent.description }}
          </dd>
        </div>
        <div
          v-if="agent?.config?.model"
          class="flex items-start gap-4 px-5 py-3"
        >
          <dt class="w-32 shrink-0 text-xs text-n-slate-10">Modelo</dt>
          <dd class="text-sm font-mono text-n-slate-12">
            {{ agent.config.model }}
          </dd>
        </div>
        <div
          v-if="agent?.config?.temperature != null"
          class="flex items-start gap-4 px-5 py-3"
        >
          <dt class="w-32 shrink-0 text-xs text-n-slate-10">Temperatura</dt>
          <dd class="text-sm font-mono text-n-slate-12">
            {{ agent.config.temperature }}
          </dd>
        </div>
        <div
          v-if="agent?.config?.product_name"
          class="flex items-start gap-4 px-5 py-3"
        >
          <dt class="w-32 shrink-0 text-xs text-n-slate-10">Produto</dt>
          <dd class="text-sm text-n-slate-12">
            {{ agent.config.product_name }}
          </dd>
        </div>
        <div
          v-if="agent?.guardrails?.length"
          class="flex items-start gap-4 px-5 py-3"
        >
          <dt class="w-32 shrink-0 text-xs text-n-slate-10">Guardrails</dt>
          <dd class="flex flex-wrap gap-1.5">
            <span
              v-for="(rule, idx) in agent.guardrails"
              :key="idx"
              class="rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-11"
            >
              {{ rule }}
            </span>
          </dd>
        </div>
      </dl>
    </div>

    <!-- Full JSON (expandible) -->
    <div class="overflow-hidden rounded-xl border border-n-weak">
      <div
        class="flex items-center justify-between border-b border-n-weak bg-n-alpha-1 px-4 py-2"
      >
        <span class="flex items-center gap-2 font-mono text-xs text-n-slate-10">
          <i class="i-lucide-file-json size-3.5" />
          assistant.json
        </span>
        <button
          class="flex items-center gap-1 text-xs text-n-slate-10 transition-colors hover:text-n-slate-12"
          @click="copyConfig"
        >
          <i
            :class="
              copied
                ? 'i-lucide-check size-3 text-green-600'
                : 'i-lucide-clipboard size-3'
            "
          />
          {{ copied ? 'Copiado!' : 'Copiar' }}
        </button>
      </div>
      <pre
        class="max-h-96 overflow-auto bg-slate-950 p-4 font-mono text-xs text-slate-300 whitespace-pre-wrap"
        >{{ fullConfig }}</pre
      >
    </div>

    <!-- API Endpoint Info -->
    <div class="flex items-start gap-2 rounded-xl bg-n-alpha-1 p-4">
      <i class="i-lucide-terminal mt-0.5 size-4 shrink-0 text-n-slate-10" />
      <div class="text-xs text-n-slate-10">
        <p class="mb-1 font-medium text-n-slate-11">Editar via API</p>
        <pre class="mt-2 rounded bg-slate-950 p-2 font-mono text-slate-400">
PUT /api/v1/accounts/:account_id/captain/assistants/{{ assistantId }}</pre
        >
      </div>
    </div>

    <!-- Danger Zone -->
    <div
      class="rounded-xl border border-red-200 bg-red-50 p-5 dark:border-red-800 dark:bg-red-900/20"
    >
      <h3
        class="flex items-center gap-2 text-sm font-semibold text-red-700 dark:text-red-400"
      >
        <i class="i-lucide-alert-triangle size-4" />
        {{ t('CAPTAIN.AGENT_TABS.SETTINGS.DANGER_ZONE') }}
      </h3>
      <p class="mt-1 text-sm text-red-600 dark:text-red-400/80">
        {{ t('CAPTAIN.AGENT_TABS.SETTINGS.DANGER_DESCRIPTION') }}
      </p>
      <div class="mt-4">
        <button
          v-if="!showDeleteConfirm"
          type="button"
          class="rounded-lg border border-red-200 bg-transparent px-3 py-1.5 text-sm font-medium text-red-600 transition-colors hover:bg-red-100 dark:border-red-800 dark:text-red-400 dark:hover:bg-red-900/30"
          @click="showDeleteConfirm = true"
        >
          {{ t('CAPTAIN.AGENT_TABS.SETTINGS.DELETE_AGENT') }}
        </button>
        <div v-else class="flex items-center gap-2">
          <span class="text-sm text-red-700 dark:text-red-400">
            {{ t('CAPTAIN.AGENT_TABS.SETTINGS.CONFIRM_DELETE') }}
          </span>
          <button
            type="button"
            class="rounded-lg bg-red-600 px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-red-700"
            @click="deleteAgent"
          >
            {{ t('CAPTAIN.AGENT_TABS.SETTINGS.YES_DELETE') }}
          </button>
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-1.5 text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-3"
            @click="showDeleteConfirm = false"
          >
            {{ t('CAPTAIN.AGENT_TABS.SETTINGS.CANCEL') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
<!-- eslint-enable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
