<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useClipboard } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';

import AiCard from 'dashboard/components-next/agents-ui/AiCard.vue';
import AiField from 'dashboard/components-next/agents-ui/AiField.vue';
import AiTextarea from 'dashboard/components-next/agents-ui/AiTextarea.vue';
import AiNumberField from 'dashboard/components-next/agents-ui/AiNumberField.vue';
import AiToggle from 'dashboard/components-next/agents-ui/AiToggle.vue';
import AiButton from 'dashboard/components-next/agents-ui/AiButton.vue';
import AiListGroup from 'dashboard/components-next/agents-ui/AiListGroup.vue';
import AiListRow from 'dashboard/components-next/agents-ui/AiListRow.vue';
import AgentSettingField from 'dashboard/components-next/agents/AgentSettingField.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { copy, copied } = useClipboard({ copiedDuring: 2000 });

const assistantId = computed(() => Number(route.params.assistantId));
const agent = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

// --- Formulário (hidratado de agent + agent.config) ---
const DEFAULT_TEMPERATURE = 0.7;

const form = reactive({
  description: '',
  responseGuidelines: '', // textarea, uma por linha
  guardrails: '', // textarea, uma por linha
  productName: '',
  temperature: DEFAULT_TEMPERATURE,
  instructions: '',
  welcomeMessage: '',
  handoffMessage: '',
  resolutionMessage: '',
  featureFaq: false,
  featureMemory: false,
  featureCitation: false,
  featureContactAttributes: false,
  tools: [],
});

// Toggles de recursos (feature_*) renderizados como lista.
const FEATURE_ROWS = [
  {
    key: 'featureFaq',
    title: 'Base de FAQ',
    subtitle: 'Consulta perguntas e respostas cadastradas para responder.',
    icon: 'i-lucide-book-open',
    tint: '#0a84ff',
  },
  {
    key: 'featureMemory',
    title: 'Memória do contato',
    subtitle: 'Lembra de informações do cliente entre conversas.',
    icon: 'i-lucide-brain',
    tint: '#5e5ce6',
  },
  {
    key: 'featureCitation',
    title: 'Citar fontes',
    subtitle: 'Mostra de onde a resposta veio (FAQ ou documento).',
    icon: 'i-lucide-quote',
    tint: '#1faa59',
  },
  {
    key: 'featureContactAttributes',
    title: 'Atributos do contato',
    subtitle: 'Usa os dados cadastrados do contato no atendimento.',
    icon: 'i-lucide-id-card',
    tint: '#ff9500',
  },
];

function snapshotOf() {
  return JSON.stringify({ ...form, tools: [...form.tools].sort() });
}
const savedSnapshot = ref('');

function hydrate(record) {
  const c = record?.config || {};
  form.description = record?.description || '';
  form.responseGuidelines = (record?.response_guidelines || []).join('\n');
  form.guardrails = (record?.guardrails || []).join('\n');
  form.productName = c.product_name || '';
  form.temperature =
    c.temperature != null ? Number(c.temperature) : DEFAULT_TEMPERATURE;
  form.instructions = c.instructions || '';
  form.welcomeMessage = c.welcome_message || '';
  form.handoffMessage = c.handoff_message || '';
  form.resolutionMessage = c.resolution_message || '';
  form.featureFaq = Boolean(c.feature_faq);
  form.featureMemory = Boolean(c.feature_memory);
  form.featureCitation = Boolean(c.feature_citation);
  form.featureContactAttributes = Boolean(c.feature_contact_attributes);
  form.tools = Array.isArray(c.tools) ? c.tools.map(String) : [];
  savedSnapshot.value = snapshotOf();
}

// Re-hidrata quando o agente carrega ou troca (não durante edição do mesmo id).
watch(
  () => agent.value?.id,
  () => hydrate(agent.value),
  { immediate: true }
);

const isDirty = computed(() => snapshotOf() !== savedSnapshot.value);
const descriptionTooLong = computed(() => form.description.length > 255);

// --- Catálogo de ferramentas (real, via backend) ---
const toolsCatalog = computed(() => {
  const seen = new Set();
  return (store.getters['captainTools/getRecords'] || []).filter(tool => {
    if (!tool?.id || seen.has(tool.id)) return false;
    seen.add(tool.id);
    return true;
  });
});
const toolsLoading = computed(
  () => store.getters['captainTools/getUIFlags'].fetchingList
);
const armedToolsCount = computed(
  () => toolsCatalog.value.filter(tool => form.tools.includes(tool.id)).length
);

function isToolArmed(id) {
  return form.tools.includes(id);
}
function toggleTool(id) {
  if (form.tools.includes(id)) {
    form.tools = form.tools.filter(toolId => toolId !== id);
  } else {
    form.tools = [...form.tools, id];
  }
}

onMounted(() => {
  store.dispatch('captainTools/getTools');
});

// --- Salvar (description/guidelines/guardrails + config completo) ---
const saving = ref(false);

const splitLines = value =>
  value
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean);

async function save() {
  if (saving.value || descriptionTooLong.value || !isDirty.value) return;
  saving.value = true;
  try {
    const config = {
      ...(agent.value?.config || {}),
      product_name: form.productName.trim(),
      temperature: Number(form.temperature),
      instructions: form.instructions,
      welcome_message: form.welcomeMessage,
      handoff_message: form.handoffMessage,
      resolution_message: form.resolutionMessage,
      feature_faq: form.featureFaq,
      feature_memory: form.featureMemory,
      feature_citation: form.featureCitation,
      feature_contact_attributes: form.featureContactAttributes,
      tools: [...form.tools],
    };
    await store.dispatch('captainAssistants/update', {
      id: assistantId.value,
      description: form.description.trim(),
      response_guidelines: splitLines(form.responseGuidelines),
      guardrails: splitLines(form.guardrails),
      config,
    });
    savedSnapshot.value = snapshotOf();
    useAlert(t('CAPTAIN.AGENT_TABS.SETTINGS.SAVE_SUCCESS'));
  } catch {
    useAlert(t('CAPTAIN.AGENT_TABS.SETTINGS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
}

function revert() {
  hydrate(agent.value);
}

// --- JSON / cópia ---
const fullConfig = computed(() => {
  if (!agent.value?.id) return '';
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

// --- Exclusão ---
const showDeleteConfirm = ref(false);
async function deleteAgent() {
  await store.dispatch('captainAssistants/delete', assistantId.value);
  useAlert(t('CAPTAIN.AGENT_TABS.SETTINGS.DELETE_SUCCESS'));
  router.push({ name: 'agents_dashboard' });
}
</script>

<!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
<template>
  <div class="px-6 pt-4 pb-16 mx-auto space-y-6 max-w-3xl">
    <!-- Barra de ações -->
    <div
      class="flex sticky top-0 z-10 gap-3 justify-between items-center py-3 -mx-6 px-6 border-b border-n-weak bg-n-solid-1"
    >
      <div class="min-w-0">
        <h2 class="text-[15px] font-bold text-n-slate-12">
          Configurações do agente
        </h2>
        <p class="text-[12px] text-n-slate-10">
          Tudo que define como o agente atende. Edite e salve.
        </p>
      </div>
      <div class="flex flex-none gap-2 items-center">
        <span v-if="isDirty" class="text-[12px] text-n-slate-10">
          Alterações não salvas
        </span>
        <AiButton
          variant="ghost"
          :disabled="!isDirty || saving"
          @click="revert"
        >
          Reverter
        </AiButton>
        <AiButton
          :disabled="!isDirty || saving || descriptionTooLong"
          @click="save"
        >
          <span v-if="saving" class="i-lucide-loader-2 size-4 animate-spin" />
          <span v-else class="i-lucide-check size-4" />
          Salvar alterações
        </AiButton>
      </div>
    </div>

    <!-- Identidade & prompt base -->
    <AiCard
      title="Identidade e prompt"
      description="Quem é o agente e como ele deve se comportar."
    >
      <div class="space-y-5">
        <AgentSettingField
          label="Descrição"
          hint="Resumo curto do papel do agente (usado no prompt)."
        >
          <template #aside>
            <span
              class="text-[11px]"
              :class="descriptionTooLong ? 'text-r-500' : 'text-n-slate-9'"
            >
              {{ form.description.length }}/255
            </span>
          </template>
          <AiTextarea v-model="form.description" :rows="3" />
        </AgentSettingField>

        <AgentSettingField
          label="Diretrizes de resposta"
          hint="Uma por linha. Como o agente deve responder (tom, formato)."
        >
          <AiTextarea v-model="form.responseGuidelines" :rows="6" />
        </AgentSettingField>

        <AgentSettingField
          label="Guardrails"
          hint="Uma por linha. Limites e regras que o agente nunca deve quebrar."
        >
          <AiTextarea v-model="form.guardrails" :rows="5" />
        </AgentSettingField>
      </div>
    </AiCard>

    <!-- Comportamento geral -->
    <AiCard
      title="Comportamento"
      description="Ajustes gerais de geração de resposta."
    >
      <div class="space-y-5">
        <AgentSettingField
          label="Nome do produto / serviço"
          hint="Como o agente se refere ao que está vendendo ou atendendo."
        >
          <AiField
            v-model="form.productName"
            placeholder="Ex.: Imobiliária Tozi"
          />
        </AgentSettingField>

        <AgentSettingField
          label="Temperatura"
          hint="0 = objetivo e previsível, 2 = criativo e variado. Padrão 0.7."
        >
          <AiNumberField
            v-model="form.temperature"
            :min="0"
            :max="2"
            :step="0.1"
          />
        </AgentSettingField>
      </div>
    </AiCard>

    <!-- Recursos (feature flags) -->
    <div>
      <p
        class="px-1 pb-2 text-[12.5px] font-bold tracking-wide uppercase text-n-slate-10"
      >
        Recursos
      </p>
      <AiListGroup>
        <AiListRow
          v-for="row in FEATURE_ROWS"
          :key="row.key"
          :title="row.title"
          :subtitle="row.subtitle"
        >
          <template #leading>
            <span
              class="grid place-items-center text-white rounded-lg size-[30px]"
              :style="{ background: row.tint }"
            >
              <span :class="row.icon" class="size-4" />
            </span>
          </template>
          <template #trailing>
            <AiToggle v-model="form[row.key]" />
          </template>
        </AiListRow>
      </AiListGroup>
    </div>

    <!-- Mensagens automáticas -->
    <AiCard
      title="Mensagens automáticas"
      description="Textos que o agente usa em momentos-chave do atendimento."
    >
      <div class="space-y-5">
        <AgentSettingField
          label="Boas-vindas"
          hint="Primeira mensagem ao iniciar uma conversa."
        >
          <AiTextarea
            v-model="form.welcomeMessage"
            :rows="2"
            placeholder="Olá! Como posso ajudar?"
          />
        </AgentSettingField>

        <AgentSettingField
          label="Transferência para humano"
          hint="Enviada quando o agente passa a conversa para um atendente."
        >
          <AiTextarea
            v-model="form.handoffMessage"
            :rows="2"
            placeholder="Vou te transferir para um atendente, um momento."
          />
        </AgentSettingField>

        <AgentSettingField
          label="Encerramento"
          hint="Enviada quando a conversa é resolvida."
        >
          <AiTextarea
            v-model="form.resolutionMessage"
            :rows="2"
            placeholder="Posso ajudar em algo mais?"
          />
        </AgentSettingField>
      </div>
    </AiCard>

    <!-- Instruções (prompt principal) -->
    <AiCard
      title="Instruções"
      description="Prompt principal: passo a passo de como o agente deve agir."
    >
      <AiTextarea
        v-model="form.instructions"
        :rows="12"
        placeholder="Descreva em detalhes como o agente deve atender, o que perguntar, quando transferir..."
      />
    </AiCard>

    <!-- Ferramentas do agente -->
    <div>
      <div class="flex justify-between items-end px-1 pb-2">
        <div class="min-w-0">
          <p
            class="text-[12.5px] font-bold tracking-wide uppercase text-n-slate-10"
          >
            Ferramentas do agente
          </p>
          <p class="text-[12px] text-n-slate-10">
            Ações que o agente pode executar durante o atendimento.
          </p>
        </div>
        <span class="flex-none text-[12px] font-semibold text-n-slate-11">
          {{ armedToolsCount }}/{{ toolsCatalog.length }} ativas
        </span>
      </div>

      <div
        v-if="toolsLoading && !toolsCatalog.length"
        class="flex gap-2 items-center px-1 py-3 text-sm text-n-slate-10"
      >
        <span class="i-lucide-loader-2 size-3.5 animate-spin" />
        Carregando ferramentas...
      </div>

      <div
        v-else-if="!toolsCatalog.length"
        class="py-10 text-center rounded-2xl border border-dashed border-n-weak bg-n-alpha-1"
      >
        <span class="mx-auto mb-2 i-lucide-wrench size-8 text-n-slate-9" />
        <p class="text-sm text-n-slate-11">Nenhuma ferramenta disponível.</p>
      </div>

      <AiListGroup v-else>
        <AiListRow
          v-for="tool in toolsCatalog"
          :key="tool.id"
          :title="tool.title || tool.id"
          :subtitle="tool.description"
        >
          <template #leading>
            <span
              class="grid place-items-center rounded-lg size-[30px]"
              :class="
                isToolArmed(tool.id)
                  ? 'bg-n-brand text-white'
                  : 'bg-n-alpha-2 text-n-slate-10'
              "
            >
              <span class="i-lucide-wrench size-4" />
            </span>
          </template>
          <template #trailing>
            <AiToggle
              :model-value="isToolArmed(tool.id)"
              @update:model-value="toggleTool(tool.id)"
            />
          </template>
        </AiListRow>
      </AiListGroup>
    </div>

    <!-- Avançado / JSON -->
    <AiCard title="Avançado" description="Estado bruto da configuração.">
      <template #actions>
        <AiButton variant="subtle" @click="copyConfig">
          <span
            :class="
              copied ? 'i-lucide-check size-3.5' : 'i-lucide-copy size-3.5'
            "
          />
          {{ copied ? 'Copiado!' : 'Copiar' }}
        </AiButton>
      </template>
      <AiListGroup>
        <AiListRow title="Modelo">
          <template #leading>
            <span
              class="grid place-items-center text-white bg-green-500 rounded-lg size-[30px]"
            >
              <span class="i-lucide-cpu size-4" />
            </span>
          </template>
          <template #trailing>
            <span class="font-mono text-sm text-n-slate-12">
              {{ agent?.config?.model || '—' }}
            </span>
          </template>
        </AiListRow>
      </AiListGroup>
      <div
        class="overflow-auto p-4 mt-3 max-h-80 font-mono text-xs whitespace-pre-wrap rounded-xl bg-n-alpha-1 text-n-slate-11"
      >
        {{ fullConfig }}
      </div>
    </AiCard>

    <!-- Zona de perigo -->
    <AiCard>
      <div class="flex flex-wrap gap-3 justify-between items-center">
        <div class="min-w-0">
          <p class="flex gap-2 items-center text-sm font-bold text-r-500">
            <span class="i-lucide-alert-triangle size-4" />
            Excluir agente
          </p>
          <p class="mt-0.5 text-[12.5px] text-n-slate-11">
            Esta ação é permanente e não pode ser desfeita.
          </p>
        </div>
        <div class="flex flex-none gap-2 items-center">
          <template v-if="!showDeleteConfirm">
            <AiButton variant="danger" @click="showDeleteConfirm = true">
              Excluir
            </AiButton>
          </template>
          <template v-else>
            <span class="text-[12.5px] text-n-slate-11">Tem certeza?</span>
            <AiButton variant="ghost" @click="showDeleteConfirm = false">
              Cancelar
            </AiButton>
            <AiButton variant="danger" @click="deleteAgent">
              Sim, excluir
            </AiButton>
          </template>
        </div>
      </div>
    </AiCard>
  </div>
</template>
<!-- eslint-enable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
