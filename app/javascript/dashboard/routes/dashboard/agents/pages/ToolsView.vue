<script setup>
// Página GLOBAL de Ferramentas (account-scoped, SEM assistantId).
// (a) Catálogo REAL de ferramentas de sistema  -> store captainTools (GET /tools)
// (b) Ferramentas personalizadas (HTTP) CRUD    -> store captainCustomTools
// (c) MCP — placeholder informativo "em breve funcional"
// Kit exclusivo: components-next/agents-ui/*. Nada legado.
import { ref, reactive, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useClipboard } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';

import AiCard from 'dashboard/components-next/agents-ui/AiCard.vue';
import AiButton from 'dashboard/components-next/agents-ui/AiButton.vue';
import AiSearch from 'dashboard/components-next/agents-ui/AiSearch.vue';
import AiBadge from 'dashboard/components-next/agents-ui/AiBadge.vue';
import AiEmptyState from 'dashboard/components-next/agents-ui/AiEmptyState.vue';
import AiModal from 'dashboard/components-next/agents-ui/AiModal.vue';
import AiField from 'dashboard/components-next/agents-ui/AiField.vue';
import AiTextarea from 'dashboard/components-next/agents-ui/AiTextarea.vue';
import AiSelect from 'dashboard/components-next/agents-ui/AiSelect.vue';
import AiCheckbox from 'dashboard/components-next/agents-ui/AiCheckbox.vue';
import AiDropdown from 'dashboard/components-next/agents-ui/AiDropdown.vue';
import AiToggle from 'dashboard/components-next/agents-ui/AiToggle.vue';
import IntegrationsAPI from 'dashboard/api/captain/integrations';

const { t } = useI18n();
const store = useStore();

// ── Stores REAIS ───────────────────────────────────────────────────────────
const builtinTools = computed(
  () => store.getters['captainTools/getRecords'] || []
);
const builtinLoading = computed(
  () => store.getters['captainTools/getUIFlags']?.fetchingList || false
);
const customTools = computed(
  () => store.getters['captainCustomTools/getRecords'] || []
);
const customLoading = computed(
  () => store.getters['captainCustomTools/getUIFlags']?.fetchingList || false
);

onMounted(() => {
  store.dispatch('captainTools/getTools');
  store.dispatch('captainCustomTools/get');
});

const search = ref('');

// ── pt-BR: mapa de fallback (só pros ids que o backend devolve em inglês).
//    Quando há tradução aqui, ela prevalece; senão usa o title/description do
//    backend (a maioria das tools do tools.yml já vem em pt-BR).
const TOOL_PT = {
  add_contact_note: {
    title: 'Adicionar nota ao contato',
    description: 'Registra uma observação no perfil de um contato',
  },
  add_private_note: {
    title: 'Adicionar nota interna',
    description: 'Registra uma nota privada na conversa (só para a equipe)',
  },
  update_priority: {
    title: 'Alterar prioridade',
    description: 'Atualiza o nível de prioridade da conversa',
  },
  add_label_to_conversation: {
    title: 'Adicionar etiqueta',
    description: 'Marca a conversa com uma etiqueta',
  },
  faq_lookup: {
    title: 'Consultar FAQ',
    description: 'Busca respostas no FAQ por similaridade semântica',
  },
  resolve_conversation: {
    title: 'Resolver conversa',
    description: 'Encerra a conversa quando o atendimento termina',
  },
  handoff: {
    title: 'Transferir para humano',
    description: 'Passa a conversa para um atendente humano',
  },
  search_knowledge: {
    title: 'Buscar na base de conhecimento',
    description:
      'Procura trechos nos documentos (RAG) por busca semântica e por termo exato',
  },
};

// Ícones do backend (tools.yml) -> classe lucide do kit. Default: wrench.
const ICON_MAP = {
  'arrow-swap': 'i-lucide-arrow-left-right',
  book: 'i-lucide-book-open',
  checkmark: 'i-lucide-circle-check-big',
  clock: 'i-lucide-clock',
  'exclamation-triangle': 'i-lucide-triangle-alert',
  'eye-off': 'i-lucide-eye-off',
  home: 'i-lucide-home',
  image: 'i-lucide-image',
  location: 'i-lucide-map-pin',
  'note-add': 'i-lucide-notebook-pen',
  person: 'i-lucide-user-round',
  search: 'i-lucide-search',
  tag: 'i-lucide-tag',
  'user-switch': 'i-lucide-user-round-cog',
};

const norm = s => (s || '').toString().toLowerCase().trim();
const humanize = id =>
  (id || '')
    .toString()
    .replace(/[_-]+/g, ' ')
    .replace(/^./, c => c.toUpperCase())
    .trim();

const toolTitle = tool =>
  TOOL_PT[tool.id]?.title || tool.title || humanize(tool.id);
const toolDesc = tool =>
  TOOL_PT[tool.id]?.description || tool.description || '';
const toolIcon = tool => ICON_MAP[tool.icon] || 'i-lucide-wrench';

// Catálogo = só tools de sistema (as custom têm flag `custom:true` no /tools).
const filteredBuiltin = computed(() => {
  const list = builtinTools.value.filter(x => !x.custom);
  const q = norm(search.value);
  if (!q) return list;
  return list.filter(
    x => norm(toolTitle(x)).includes(q) || norm(toolDesc(x)).includes(q)
  );
});

const filteredCustom = computed(() => {
  const q = norm(search.value);
  const list = customTools.value;
  if (!q) return list;
  return list.filter(
    x => norm(x.title).includes(q) || norm(x.description).includes(q)
  );
});

// ── Form de custom tool (campos CORRETOS do backend) ────────────────────────
const HTTP_METHODS = [
  { value: 'GET', label: 'GET' },
  { value: 'POST', label: 'POST' },
];
const AUTH_TYPES = computed(() => [
  { value: 'none', label: t('AGENTS_TOOLS.FORM.AUTH.NONE') },
  { value: 'bearer', label: t('AGENTS_TOOLS.FORM.AUTH.BEARER') },
  { value: 'basic', label: t('AGENTS_TOOLS.FORM.AUTH.BASIC') },
  { value: 'api_key', label: t('AGENTS_TOOLS.FORM.AUTH.API_KEY') },
]);
const PARAM_TYPES = computed(() => [
  { value: 'string', label: t('AGENTS_TOOLS.FORM.TYPE.STRING') },
  { value: 'number', label: t('AGENTS_TOOLS.FORM.TYPE.NUMBER') },
  { value: 'boolean', label: t('AGENTS_TOOLS.FORM.TYPE.BOOLEAN') },
]);

const showForm = ref(false);
const editingId = ref(null);
const saving = ref(false);
let pid = 0;

const form = reactive({
  title: '',
  description: '',
  endpoint_url: '',
  http_method: 'GET',
  auth_type: 'none',
  auth: {
    token: '',
    username: '',
    password: '',
    headerName: '',
    headerKey: '',
  },
  params: [],
});

function resetForm() {
  form.title = '';
  form.description = '';
  form.endpoint_url = '';
  form.http_method = 'GET';
  form.auth_type = 'none';
  form.auth = {
    token: '',
    username: '',
    password: '',
    headerName: '',
    headerKey: '',
  };
  form.params = [];
  editingId.value = null;
}

function addParam() {
  pid += 1;
  form.params.push({
    _id: pid,
    name: '',
    type: 'string',
    description: '',
    required: false,
  });
}
function removeParam(index) {
  form.params.splice(index, 1);
}

function openCreate() {
  resetForm();
  showForm.value = true;
}
function openEdit(tool) {
  resetForm();
  editingId.value = tool.id;
  form.title = tool.title || '';
  form.description = tool.description || '';
  form.endpoint_url = tool.endpoint_url || '';
  form.http_method = tool.http_method || 'GET';
  form.auth_type = tool.auth_type || 'none';
  const ac = tool.auth_config || {};
  form.auth.token = ac.token || '';
  form.auth.username = ac.username || '';
  form.auth.password = ac.password || '';
  form.auth.headerName = ac.name || '';
  form.auth.headerKey = ac.key || '';
  form.params = (tool.param_schema || []).map(p => {
    pid += 1;
    return {
      _id: pid,
      name: p.name || '',
      type: p.type || 'string',
      description: p.description || '',
      required: Boolean(p.required),
    };
  });
  showForm.value = true;
}
function closeForm() {
  showForm.value = false;
  resetForm();
}

function buildAuthConfig() {
  switch (form.auth_type) {
    case 'bearer':
      return { token: form.auth.token };
    case 'basic':
      return { username: form.auth.username, password: form.auth.password };
    case 'api_key':
      // backend só injeta header quando location === 'header'
      return {
        location: 'header',
        name: form.auth.headerName,
        key: form.auth.headerKey,
      };
    default:
      return {};
  }
}
function buildParamSchema() {
  return form.params
    .filter(p => p.name.trim())
    .map(p => ({
      name: p.name.trim(),
      type: p.type || 'string',
      description: p.description || '',
      required: Boolean(p.required),
    }));
}

const canSave = computed(
  () => Boolean(form.title.trim()) && Boolean(form.endpoint_url.trim())
);

async function submitForm() {
  if (!canSave.value) {
    useAlert(t('AGENTS_TOOLS.MESSAGES.VALIDATION'));
    return;
  }
  saving.value = true;
  const payload = {
    title: form.title.trim(),
    description: form.description.trim(),
    endpoint_url: form.endpoint_url.trim(),
    http_method: form.http_method,
    auth_type: form.auth_type,
    auth_config: buildAuthConfig(),
    param_schema: buildParamSchema(),
  };
  const isEdit = Boolean(editingId.value);
  try {
    if (isEdit) {
      await store.dispatch('captainCustomTools/update', {
        id: editingId.value,
        ...payload,
      });
      useAlert(t('AGENTS_TOOLS.MESSAGES.UPDATE_SUCCESS'));
    } else {
      await store.dispatch('captainCustomTools/create', payload);
      useAlert(t('AGENTS_TOOLS.MESSAGES.CREATE_SUCCESS'));
    }
    closeForm();
  } catch {
    useAlert(
      isEdit
        ? t('AGENTS_TOOLS.MESSAGES.UPDATE_ERROR')
        : t('AGENTS_TOOLS.MESSAGES.CREATE_ERROR')
    );
  } finally {
    saving.value = false;
  }
}

async function toggleEnabled(tool) {
  try {
    await store.dispatch('captainCustomTools/update', {
      id: tool.id,
      enabled: !tool.enabled,
    });
    useAlert(t('AGENTS_TOOLS.MESSAGES.UPDATE_SUCCESS'));
  } catch {
    useAlert(t('AGENTS_TOOLS.MESSAGES.UPDATE_ERROR'));
  }
}

// ── Exclusão com confirmação (AiModal) ──────────────────────────────────────
const deleteTarget = ref(null);
const deleting = ref(false);
const deleteConfirmText = computed(() =>
  t('AGENTS_TOOLS.DELETE.CONFIRM', { name: deleteTarget.value?.title || '' })
);
function askDelete(tool) {
  deleteTarget.value = tool;
}
function cancelDelete() {
  deleteTarget.value = null;
}
async function confirmDelete() {
  if (!deleteTarget.value) return;
  deleting.value = true;
  try {
    await store.dispatch('captainCustomTools/delete', deleteTarget.value.id);
    useAlert(t('AGENTS_TOOLS.MESSAGES.DELETE_SUCCESS'));
    deleteTarget.value = null;
  } catch {
    useAlert(t('AGENTS_TOOLS.MESSAGES.DELETE_ERROR'));
  } finally {
    deleting.value = false;
  }
}

function rowActions(tool) {
  return [
    {
      value: 'edit',
      label: t('AGENTS_TOOLS.ACTIONS.EDIT'),
      icon: 'i-lucide-pencil',
    },
    {
      value: 'toggle',
      label: tool.enabled
        ? t('AGENTS_TOOLS.ACTIONS.DISABLE')
        : t('AGENTS_TOOLS.ACTIONS.ENABLE'),
      icon: tool.enabled ? 'i-lucide-pause' : 'i-lucide-play',
    },
    {
      value: 'delete',
      label: t('AGENTS_TOOLS.ACTIONS.DELETE'),
      icon: 'i-lucide-trash-2',
      danger: true,
    },
  ];
}
function onRowAction(tool, action) {
  if (action === 'edit') openEdit(tool);
  else if (action === 'delete') askDelete(tool);
  else if (action === 'toggle') toggleEnabled(tool);
}

// ── MCP (placeholder + snippet copiável) ────────────────────────────────────
const { copy: copyMcp, copied: copiedMcp } = useClipboard({
  copiedDuring: 2000,
});
const mcpTemplate = JSON.stringify(
  {
    mcpServers: {
      chatspx: {
        command: 'npx',
        args: ['-y', '@anthropic/mcp-server-chatspx'],
        env: {
          CHATSPX_API_URL: 'https://chatspx.app',
          CHATSPX_API_TOKEN: 'your-api-token-here',
        },
      },
    },
  },
  null,
  2
);
function copyMcpTemplate() {
  copyMcp(mcpTemplate);
}

// ── (d) Integrações de provedores (Vista/Loft, Google) ──────────────────────
// Chama a API direto (sem store). Segredos chegam MASCARADOS e só são reenviados
// se o usuário trocar o valor (campo sem '*').
const integrations = ref([]);
const integrationsLoading = ref(false);

async function loadIntegrations() {
  integrationsLoading.value = true;
  try {
    const { data } = await IntegrationsAPI.get();
    integrations.value = Array.isArray(data) ? data : data?.payload || [];
  } catch {
    integrations.value = [];
  } finally {
    integrationsLoading.value = false;
  }
}

const findIntegration = provider =>
  integrations.value.find(i => i.provider === provider);

// Conectado = habilitado E com algum valor de configuração presente.
function isConnected(provider) {
  const rec = findIntegration(provider);
  if (!rec || !rec.enabled) return false;
  const s = rec.settings || {};
  return Object.values(s).some(v => v !== '' && v !== null && v !== undefined);
}

const PROVIDER_NAME = {
  vista: () => t('AGENTS_TOOLS.INTEGRATIONS.VISTA.NAME'),
  google: () => t('AGENTS_TOOLS.INTEGRATIONS.GOOGLE.NAME'),
};

// Modal de configuração
const dialogProvider = ref(null);
const savingIntegration = ref(false);
const testing = ref(false);
const testResult = ref(null);

const integrationForm = reactive({
  enabled: false,
  // Vista
  vista_api_key: '',
  vista_base_url: '',
  office_name: '',
  office_lat: '',
  office_lng: '',
  site_domain: '',
  // Google
  google_maps_key: '',
});

const dialogTitle = computed(() => {
  const name = dialogProvider.value
    ? PROVIDER_NAME[dialogProvider.value]?.()
    : '';
  return name ? `${t('AGENTS_TOOLS.INTEGRATIONS.CONFIGURE')} · ${name}` : '';
});

function resetIntegrationForm() {
  integrationForm.enabled = false;
  integrationForm.vista_api_key = '';
  integrationForm.vista_base_url = '';
  integrationForm.office_name = '';
  integrationForm.office_lat = '';
  integrationForm.office_lng = '';
  integrationForm.site_domain = '';
  integrationForm.google_maps_key = '';
}

const asStr = v => (v === null || v === undefined ? '' : String(v));

function openConfigure(provider) {
  resetIntegrationForm();
  testResult.value = null;
  dialogProvider.value = provider;
  const rec = findIntegration(provider) || {};
  const s = rec.settings || {};
  integrationForm.enabled = Boolean(rec.enabled);
  if (provider === 'vista') {
    integrationForm.vista_api_key = asStr(s.vista_api_key);
    integrationForm.vista_base_url = asStr(s.vista_base_url);
    integrationForm.office_name = asStr(s.office_name);
    integrationForm.office_lat = asStr(s.office_lat);
    integrationForm.office_lng = asStr(s.office_lng);
    integrationForm.site_domain = asStr(s.site_domain);
  } else if (provider === 'google') {
    integrationForm.google_maps_key = asStr(s.google_maps_key);
  }
}

function closeConfigure() {
  dialogProvider.value = null;
  testResult.value = null;
  resetIntegrationForm();
}

// Segredo mascarado (contém '*') NÃO é reenviado, pra não sobrescrever no backend.
const isMasked = v => typeof v === 'string' && v.includes('*');

function buildSettings(provider) {
  const s = {};
  if (provider === 'vista') {
    if (!isMasked(integrationForm.vista_api_key)) {
      s.vista_api_key = integrationForm.vista_api_key;
    }
    s.vista_base_url = integrationForm.vista_base_url;
    s.office_name = integrationForm.office_name;
    s.office_lat = integrationForm.office_lat;
    s.office_lng = integrationForm.office_lng;
    s.site_domain = integrationForm.site_domain;
  } else if (provider === 'google') {
    if (!isMasked(integrationForm.google_maps_key)) {
      s.google_maps_key = integrationForm.google_maps_key;
    }
  }
  return s;
}

async function testIntegrationConnection() {
  const provider = dialogProvider.value;
  if (!provider) return;
  testing.value = true;
  testResult.value = null;
  try {
    const { data } = await IntegrationsAPI.testConnection(provider);
    testResult.value = { ok: Boolean(data?.ok), status: data?.status };
  } catch (e) {
    testResult.value = {
      ok: false,
      status: e?.response?.data?.status || e?.response?.status || 'error',
    };
  } finally {
    testing.value = false;
  }
}

async function saveIntegration() {
  const provider = dialogProvider.value;
  if (!provider) return;
  savingIntegration.value = true;
  try {
    await IntegrationsAPI.update(provider, {
      enabled: integrationForm.enabled,
      settings: buildSettings(provider),
    });
    useAlert(t('AGENTS_TOOLS.INTEGRATIONS.SAVE_SUCCESS'));
    await loadIntegrations();
    closeConfigure();
  } catch {
    useAlert(t('AGENTS_TOOLS.INTEGRATIONS.SAVE_ERROR'));
  } finally {
    savingIntegration.value = false;
  }
}

onMounted(loadIntegrations);
</script>

<template>
  <div class="px-6 pt-5 pb-12 mx-auto space-y-8 max-w-5xl">
    <!-- Header -->
    <div class="space-y-1">
      <h1 class="text-[22px] font-extrabold tracking-tight text-n-slate-12">
        {{ t('AGENTS_TOOLS.TITLE') }}
      </h1>
      <p class="text-[13px] text-n-slate-11">
        {{ t('AGENTS_TOOLS.SUBTITLE') }}
      </p>
    </div>

    <AiSearch
      v-model="search"
      :placeholder="t('AGENTS_TOOLS.SEARCH_PLACEHOLDER')"
    />

    <!-- (a) Ferramentas de sistema -->
    <section class="space-y-3">
      <header class="flex gap-2.5 items-center px-1">
        <span
          class="grid flex-none place-items-center text-white rounded-lg size-6 bg-n-brand"
        >
          <span class="i-lucide-sparkles size-4" />
        </span>
        <h2 class="text-sm font-bold text-n-slate-12">
          {{ t('AGENTS_TOOLS.SECTION_BUILTIN') }}
        </h2>
        <span class="text-xs font-medium text-n-slate-10">
          {{ filteredBuiltin.length }}
        </span>
      </header>

      <div
        v-if="builtinLoading"
        class="flex gap-2 items-center px-1 text-sm text-n-slate-10"
      >
        <span class="i-lucide-loader-2 size-4 animate-spin" />
        {{ t('AGENTS_TOOLS.LOADING') }}
      </div>

      <div v-else-if="filteredBuiltin.length" class="grid gap-3 sm:grid-cols-2">
        <AiCard
          v-for="tool in filteredBuiltin"
          :key="tool.id"
          :title="toolTitle(tool)"
          :description="toolDesc(tool)"
        >
          <template #leading>
            <span
              class="grid flex-none place-items-center rounded-xl size-9 text-n-brand bg-n-alpha-2"
            >
              <span :class="toolIcon(tool)" class="size-[18px]" />
            </span>
          </template>
          <template #actions>
            <AiBadge variant="off" :label="t('AGENTS_TOOLS.SYSTEM_BADGE')" />
          </template>
        </AiCard>
      </div>

      <AiEmptyState
        v-else
        icon="i-lucide-search-x"
        :title="t('AGENTS_TOOLS.EMPTY_BUILTIN_TITLE')"
        :description="t('AGENTS_TOOLS.EMPTY_BUILTIN_DESC')"
      />
    </section>

    <!-- (b) Ferramentas personalizadas (HTTP) -->
    <section class="space-y-3">
      <header class="flex gap-3 justify-between items-center px-1">
        <div class="flex gap-2.5 items-center">
          <span
            class="grid flex-none place-items-center text-white rounded-lg size-6 bg-n-slate-9"
          >
            <span class="i-lucide-wrench size-4" />
          </span>
          <h2 class="text-sm font-bold text-n-slate-12">
            {{ t('AGENTS_TOOLS.SECTION_CUSTOM') }}
          </h2>
          <span class="text-xs font-medium text-n-slate-10">
            {{ filteredCustom.length }}
          </span>
        </div>
        <AiButton variant="ghost" @click="openCreate">
          <span class="i-lucide-plus size-4" />
          {{ t('AGENTS_TOOLS.NEW_TOOL') }}
        </AiButton>
      </header>

      <div
        v-if="customLoading"
        class="flex gap-2 items-center px-1 text-sm text-n-slate-10"
      >
        <span class="i-lucide-loader-2 size-4 animate-spin" />
        {{ t('AGENTS_TOOLS.LOADING') }}
      </div>

      <div v-else-if="filteredCustom.length" class="grid gap-3 sm:grid-cols-2">
        <AiCard
          v-for="tool in filteredCustom"
          :key="tool.id"
          :title="tool.title"
          :description="tool.description || ''"
        >
          <template #leading>
            <span
              class="grid flex-none place-items-center text-white rounded-xl size-9 bg-n-slate-9"
            >
              <span class="i-lucide-wrench size-[18px]" />
            </span>
          </template>
          <template #actions>
            <div class="flex gap-1.5 items-center">
              <AiBadge
                :variant="tool.enabled ? 'on' : 'off'"
                :label="
                  tool.enabled
                    ? t('AGENTS_TOOLS.ACTIVE')
                    : t('AGENTS_TOOLS.INACTIVE')
                "
              />
              <AiDropdown
                :items="rowActions(tool)"
                @select="action => onRowAction(tool, action)"
              />
            </div>
          </template>
          <div class="flex gap-2 items-center">
            <span
              class="px-1.5 py-0.5 font-mono text-[11px] rounded bg-n-alpha-2 text-n-slate-11"
            >
              {{ tool.http_method }}
            </span>
            <span class="font-mono text-[11px] truncate text-n-slate-10">
              {{ tool.endpoint_url }}
            </span>
          </div>
        </AiCard>
      </div>

      <AiEmptyState
        v-else
        icon="i-lucide-wrench"
        :title="t('AGENTS_TOOLS.EMPTY_CUSTOM_TITLE')"
        :description="t('AGENTS_TOOLS.EMPTY_CUSTOM_DESC')"
      >
        <template #action>
          <AiButton @click="openCreate">
            <span class="i-lucide-plus size-4" />
            {{ t('AGENTS_TOOLS.NEW_TOOL') }}
          </AiButton>
        </template>
      </AiEmptyState>
    </section>

    <!-- (d) Integrações de provedores (Vista / Google) -->
    <section class="space-y-3">
      <header class="flex gap-2.5 items-center px-1">
        <span
          class="grid flex-none place-items-center text-white rounded-lg size-6 bg-n-slate-9"
        >
          <span class="i-lucide-blocks size-4" />
        </span>
        <h2 class="text-sm font-bold text-n-slate-12">
          {{ t('AGENTS_TOOLS.INTEGRATIONS.SECTION_TITLE') }}
        </h2>
      </header>

      <div
        v-if="integrationsLoading"
        class="flex gap-2 items-center px-1 text-sm text-n-slate-10"
      >
        <span class="i-lucide-loader-2 size-4 animate-spin" />
        {{ t('AGENTS_TOOLS.LOADING') }}
      </div>

      <div v-else class="grid gap-3 sm:grid-cols-2">
        <!-- Vista (Loft) -->
        <AiCard
          :title="t('AGENTS_TOOLS.INTEGRATIONS.VISTA.NAME')"
          :description="t('AGENTS_TOOLS.INTEGRATIONS.VISTA.DESCRIPTION')"
        >
          <template #leading>
            <span
              class="grid flex-none place-items-center text-white rounded-xl size-9 bg-n-brand"
            >
              <span class="i-lucide-building-2 size-[18px]" />
            </span>
          </template>
          <template #actions>
            <AiBadge
              :variant="isConnected('vista') ? 'on' : 'off'"
              :label="
                isConnected('vista')
                  ? t('AGENTS_TOOLS.INTEGRATIONS.CONNECTED')
                  : t('AGENTS_TOOLS.INTEGRATIONS.NOT_CONNECTED')
              "
            />
          </template>
          <AiButton variant="ghost" @click="openConfigure('vista')">
            <span class="i-lucide-settings-2 size-4" />
            {{ t('AGENTS_TOOLS.INTEGRATIONS.CONFIGURE') }}
          </AiButton>
        </AiCard>

        <!-- Google -->
        <AiCard
          :title="t('AGENTS_TOOLS.INTEGRATIONS.GOOGLE.NAME')"
          :description="t('AGENTS_TOOLS.INTEGRATIONS.GOOGLE.DESCRIPTION')"
        >
          <template #leading>
            <span
              class="grid flex-none place-items-center bg-white rounded-xl border size-9 border-n-weak"
            >
              <span class="i-logos-google-icon size-[18px]" />
            </span>
          </template>
          <template #actions>
            <AiBadge
              :variant="isConnected('google') ? 'on' : 'off'"
              :label="
                isConnected('google')
                  ? t('AGENTS_TOOLS.INTEGRATIONS.CONNECTED')
                  : t('AGENTS_TOOLS.INTEGRATIONS.NOT_CONNECTED')
              "
            />
          </template>
          <AiButton variant="ghost" @click="openConfigure('google')">
            <span class="i-lucide-settings-2 size-4" />
            {{ t('AGENTS_TOOLS.INTEGRATIONS.CONFIGURE') }}
          </AiButton>
        </AiCard>
      </div>
    </section>

    <!-- (c) MCP — placeholder -->
    <section class="space-y-3">
      <header class="flex gap-2.5 items-center px-1">
        <span
          class="grid flex-none place-items-center rounded-lg size-6 text-n-brand bg-n-alpha-2"
        >
          <span class="i-lucide-plug size-4" />
        </span>
        <h2 class="text-sm font-bold text-n-slate-12">
          {{ t('AGENTS_TOOLS.MCP.TITLE') }}
        </h2>
        <AiBadge variant="warn" :label="t('AGENTS_TOOLS.MCP.SOON')" />
      </header>

      <AiCard :description="t('AGENTS_TOOLS.MCP.DESCRIPTION')">
        <div class="overflow-hidden rounded-xl border border-n-weak">
          <div
            class="flex justify-between items-center px-3 py-2 border-b border-n-weak bg-n-alpha-1"
          >
            <span class="font-mono text-xs text-n-slate-10">
              {{ t('AGENTS_TOOLS.MCP.FILE') }}
            </span>
            <button
              type="button"
              class="flex gap-1 items-center text-xs transition-colors text-n-slate-10 hover:text-n-slate-12"
              @click="copyMcpTemplate"
            >
              <span
                :class="
                  copiedMcp
                    ? 'i-lucide-check size-3 text-g-600'
                    : 'i-lucide-clipboard size-3'
                "
              />
              {{
                copiedMcp
                  ? t('AGENTS_TOOLS.MCP.COPIED')
                  : t('AGENTS_TOOLS.MCP.COPY')
              }}
            </button>
          </div>
          <!-- eslint-disable prettier/prettier -->
          <pre
            class="overflow-x-auto p-3 max-h-48 font-mono text-xs text-slate-300 bg-slate-950"
            >{{ mcpTemplate }}</pre>
          <!-- eslint-enable prettier/prettier -->
        </div>
      </AiCard>
    </section>

    <!-- Form de criar/editar custom tool -->
    <AiModal
      :model-value="showForm"
      :width="640"
      :title="
        editingId
          ? t('AGENTS_TOOLS.FORM.EDIT_TITLE')
          : t('AGENTS_TOOLS.FORM.CREATE_TITLE')
      "
      @update:model-value="closeForm"
    >
      <div class="flex flex-col gap-4 max-h-[60vh] overflow-y-auto pr-1">
        <!-- Título -->
        <div>
          <label class="block mb-1.5 text-[13px] font-semibold text-n-slate-12">
            {{ t('AGENTS_TOOLS.FORM.TITLE_LABEL') }}
          </label>
          <AiField
            v-model="form.title"
            :placeholder="t('AGENTS_TOOLS.FORM.TITLE_PLACEHOLDER')"
          />
        </div>

        <!-- Descrição -->
        <div>
          <label class="block mb-1.5 text-[13px] font-semibold text-n-slate-12">
            {{ t('AGENTS_TOOLS.FORM.DESCRIPTION_LABEL') }}
          </label>
          <AiTextarea
            v-model="form.description"
            :rows="2"
            :placeholder="t('AGENTS_TOOLS.FORM.DESCRIPTION_PLACEHOLDER')"
          />
        </div>

        <!-- Endpoint -->
        <div>
          <label class="block mb-1.5 text-[13px] font-semibold text-n-slate-12">
            {{ t('AGENTS_TOOLS.FORM.ENDPOINT_LABEL') }}
          </label>
          <AiField
            v-model="form.endpoint_url"
            :placeholder="t('AGENTS_TOOLS.FORM.ENDPOINT_PLACEHOLDER')"
          />
        </div>

        <!-- Método + Auth -->
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label
              class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
            >
              {{ t('AGENTS_TOOLS.FORM.METHOD_LABEL') }}
            </label>
            <AiSelect v-model="form.http_method" :options="HTTP_METHODS" />
          </div>
          <div>
            <label
              class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
            >
              {{ t('AGENTS_TOOLS.FORM.AUTH_LABEL') }}
            </label>
            <AiSelect v-model="form.auth_type" :options="AUTH_TYPES" />
          </div>
        </div>

        <!-- Campos condicionais de auth -->
        <div v-if="form.auth_type === 'bearer'">
          <label class="block mb-1.5 text-[13px] font-semibold text-n-slate-12">
            {{ t('AGENTS_TOOLS.FORM.AUTH_FIELDS.TOKEN_LABEL') }}
          </label>
          <AiField
            v-model="form.auth.token"
            secret
            :placeholder="t('AGENTS_TOOLS.FORM.AUTH_FIELDS.TOKEN_PLACEHOLDER')"
          />
        </div>

        <div
          v-else-if="form.auth_type === 'basic'"
          class="grid grid-cols-2 gap-3"
        >
          <div>
            <label
              class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
            >
              {{ t('AGENTS_TOOLS.FORM.AUTH_FIELDS.USERNAME_LABEL') }}
            </label>
            <AiField
              v-model="form.auth.username"
              :placeholder="t('AGENTS_TOOLS.FORM.AUTH_FIELDS.USERNAME_LABEL')"
            />
          </div>
          <div>
            <label
              class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
            >
              {{ t('AGENTS_TOOLS.FORM.AUTH_FIELDS.PASSWORD_LABEL') }}
            </label>
            <AiField
              v-model="form.auth.password"
              secret
              :placeholder="t('AGENTS_TOOLS.FORM.AUTH_FIELDS.PASSWORD_LABEL')"
            />
          </div>
        </div>

        <div
          v-else-if="form.auth_type === 'api_key'"
          class="grid grid-cols-2 gap-3"
        >
          <div>
            <label
              class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
            >
              {{ t('AGENTS_TOOLS.FORM.AUTH_FIELDS.HEADER_NAME_LABEL') }}
            </label>
            <AiField
              v-model="form.auth.headerName"
              :placeholder="
                t('AGENTS_TOOLS.FORM.AUTH_FIELDS.HEADER_NAME_PLACEHOLDER')
              "
            />
          </div>
          <div>
            <label
              class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
            >
              {{ t('AGENTS_TOOLS.FORM.AUTH_FIELDS.HEADER_VALUE_LABEL') }}
            </label>
            <AiField
              v-model="form.auth.headerKey"
              secret
              :placeholder="
                t('AGENTS_TOOLS.FORM.AUTH_FIELDS.HEADER_VALUE_PLACEHOLDER')
              "
            />
          </div>
        </div>

        <!-- Editor de param_schema -->
        <div class="pt-1 space-y-2 border-t border-n-weak">
          <div class="flex justify-between items-center pt-3">
            <div>
              <p class="text-[13px] font-semibold text-n-slate-12">
                {{ t('AGENTS_TOOLS.FORM.PARAMS_LABEL') }}
              </p>
              <p class="text-[12px] text-n-slate-10">
                {{ t('AGENTS_TOOLS.FORM.PARAMS_DESC') }}
              </p>
            </div>
            <AiButton variant="subtle" @click="addParam">
              <span class="i-lucide-plus size-4" />
              {{ t('AGENTS_TOOLS.FORM.ADD_PARAM') }}
            </AiButton>
          </div>

          <p
            v-if="!form.params.length"
            class="px-1 text-[12.5px] text-n-slate-10"
          >
            {{ t('AGENTS_TOOLS.FORM.NO_PARAMS') }}
          </p>

          <div
            v-for="(param, index) in form.params"
            :key="param._id"
            class="flex gap-2 items-start p-3 rounded-xl border border-n-weak bg-n-alpha-1"
          >
            <div class="flex-1 space-y-2">
              <div class="grid grid-cols-2 gap-2">
                <AiField
                  v-model="param.name"
                  :placeholder="t('AGENTS_TOOLS.FORM.PARAM_NAME_PLACEHOLDER')"
                />
                <AiSelect v-model="param.type" :options="PARAM_TYPES" />
              </div>
              <AiField
                v-model="param.description"
                :placeholder="t('AGENTS_TOOLS.FORM.PARAM_DESC_PLACEHOLDER')"
              />
              <AiCheckbox
                v-model="param.required"
                :label="t('AGENTS_TOOLS.FORM.PARAM_REQUIRED')"
              />
            </div>
            <button
              type="button"
              class="grid flex-none place-items-center rounded-lg transition size-8 text-n-slate-11 hover:bg-n-alpha-2 hover:text-r-500"
              @click="removeParam(index)"
            >
              <span class="i-lucide-trash-2 size-4" />
            </button>
          </div>
        </div>
      </div>

      <template #footer>
        <AiButton variant="ghost" @click="closeForm">
          {{ t('AGENTS_TOOLS.FORM.CANCEL') }}
        </AiButton>
        <AiButton :disabled="!canSave || saving" @click="submitForm">
          {{
            saving ? t('AGENTS_TOOLS.FORM.SAVING') : t('AGENTS_TOOLS.FORM.SAVE')
          }}
        </AiButton>
      </template>
    </AiModal>

    <!-- Confirmação de exclusão -->
    <AiModal
      :model-value="Boolean(deleteTarget)"
      :width="420"
      :title="t('AGENTS_TOOLS.DELETE.TITLE')"
      @update:model-value="cancelDelete"
    >
      <p class="text-[13.5px] text-n-slate-11">{{ deleteConfirmText }}</p>
      <template #footer>
        <AiButton variant="ghost" @click="cancelDelete">
          {{ t('AGENTS_TOOLS.DELETE.CANCEL') }}
        </AiButton>
        <AiButton variant="danger" :disabled="deleting" @click="confirmDelete">
          {{ t('AGENTS_TOOLS.DELETE.CONFIRM_BTN') }}
        </AiButton>
      </template>
    </AiModal>

    <!-- Configurar integração (Vista / Google) -->
    <AiModal
      :model-value="Boolean(dialogProvider)"
      :width="560"
      :title="dialogTitle"
      @update:model-value="closeConfigure"
    >
      <div class="flex flex-col gap-4 max-h-[60vh] overflow-y-auto pr-1">
        <!-- Toggle Ativado -->
        <div
          class="flex gap-3 justify-between items-center p-3 rounded-xl border border-n-weak bg-n-alpha-1"
        >
          <div class="min-w-0">
            <p class="text-[13px] font-semibold text-n-slate-12">
              {{ t('AGENTS_TOOLS.INTEGRATIONS.ENABLED_LABEL') }}
            </p>
            <p class="text-[12px] text-n-slate-10">
              {{ t('AGENTS_TOOLS.INTEGRATIONS.ENABLED_DESC') }}
            </p>
          </div>
          <AiToggle v-model="integrationForm.enabled" />
        </div>

        <!-- Campos da Vista -->
        <template v-if="dialogProvider === 'vista'">
          <div>
            <label
              class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
            >
              {{ t('AGENTS_TOOLS.INTEGRATIONS.VISTA.API_KEY') }}
            </label>
            <AiField
              v-model="integrationForm.vista_api_key"
              secret
              :placeholder="
                t('AGENTS_TOOLS.INTEGRATIONS.VISTA.API_KEY_PLACEHOLDER')
              "
            />
          </div>
          <div>
            <label
              class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
            >
              {{ t('AGENTS_TOOLS.INTEGRATIONS.VISTA.BASE_URL') }}
            </label>
            <AiField
              v-model="integrationForm.vista_base_url"
              :placeholder="
                t('AGENTS_TOOLS.INTEGRATIONS.VISTA.BASE_URL_PLACEHOLDER')
              "
            />
          </div>
          <div>
            <label
              class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
            >
              {{ t('AGENTS_TOOLS.INTEGRATIONS.VISTA.OFFICE_NAME') }}
            </label>
            <AiField
              v-model="integrationForm.office_name"
              :placeholder="
                t('AGENTS_TOOLS.INTEGRATIONS.VISTA.OFFICE_NAME_PLACEHOLDER')
              "
            />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label
                class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
              >
                {{ t('AGENTS_TOOLS.INTEGRATIONS.VISTA.OFFICE_LAT') }}
              </label>
              <AiField
                v-model="integrationForm.office_lat"
                :placeholder="
                  t('AGENTS_TOOLS.INTEGRATIONS.VISTA.OFFICE_LAT_PLACEHOLDER')
                "
              />
            </div>
            <div>
              <label
                class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
              >
                {{ t('AGENTS_TOOLS.INTEGRATIONS.VISTA.OFFICE_LNG') }}
              </label>
              <AiField
                v-model="integrationForm.office_lng"
                :placeholder="
                  t('AGENTS_TOOLS.INTEGRATIONS.VISTA.OFFICE_LNG_PLACEHOLDER')
                "
              />
            </div>
          </div>
          <div>
            <label
              class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
            >
              {{ t('AGENTS_TOOLS.INTEGRATIONS.VISTA.SITE_DOMAIN') }}
            </label>
            <AiField
              v-model="integrationForm.site_domain"
              :placeholder="
                t('AGENTS_TOOLS.INTEGRATIONS.VISTA.SITE_DOMAIN_PLACEHOLDER')
              "
            />
          </div>
        </template>

        <!-- Campos do Google -->
        <template v-else-if="dialogProvider === 'google'">
          <div>
            <label
              class="block mb-1.5 text-[13px] font-semibold text-n-slate-12"
            >
              {{ t('AGENTS_TOOLS.INTEGRATIONS.GOOGLE.MAPS_KEY') }}
            </label>
            <AiField
              v-model="integrationForm.google_maps_key"
              secret
              :placeholder="
                t('AGENTS_TOOLS.INTEGRATIONS.GOOGLE.MAPS_KEY_PLACEHOLDER')
              "
            />
          </div>
        </template>

        <!-- Testar conexão + resultado inline -->
        <div class="flex flex-wrap gap-3 items-center pt-1">
          <AiButton
            variant="subtle"
            :disabled="testing"
            @click="testIntegrationConnection"
          >
            <span
              :class="
                testing
                  ? 'i-lucide-loader-2 size-4 animate-spin'
                  : 'i-lucide-plug-zap size-4'
              "
            />
            {{
              testing
                ? t('AGENTS_TOOLS.INTEGRATIONS.TESTING')
                : t('AGENTS_TOOLS.INTEGRATIONS.TEST_CONNECTION')
            }}
          </AiButton>
          <span
            v-if="testResult"
            class="inline-flex gap-1.5 items-center text-[13px] font-semibold"
            :class="testResult.ok ? 'text-g-600' : 'text-r-500'"
          >
            <span
              :class="
                testResult.ok
                  ? 'i-lucide-circle-check size-4'
                  : 'i-lucide-circle-x size-4'
              "
            />
            {{
              testResult.ok
                ? t('AGENTS_TOOLS.INTEGRATIONS.TEST_OK')
                : t('AGENTS_TOOLS.INTEGRATIONS.TEST_FAIL')
            }}
            <span
              v-if="testResult.status"
              class="font-mono text-[11px] text-n-slate-10"
            >
              {{ `(${testResult.status})` }}
            </span>
          </span>
        </div>
      </div>

      <template #footer>
        <AiButton variant="ghost" @click="closeConfigure">
          {{ t('AGENTS_TOOLS.INTEGRATIONS.CANCEL') }}
        </AiButton>
        <AiButton :disabled="savingIntegration" @click="saveIntegration">
          {{
            savingIntegration
              ? t('AGENTS_TOOLS.INTEGRATIONS.SAVING')
              : t('AGENTS_TOOLS.INTEGRATIONS.SAVE')
          }}
        </AiButton>
      </template>
    </AiModal>
  </div>
</template>
