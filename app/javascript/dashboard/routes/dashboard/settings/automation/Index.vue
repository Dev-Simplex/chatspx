<script setup>
import { useAlert } from 'dashboard/composables';
import AddAutomationRule from './AddAutomationRule.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { picoSearch } from '@scmmishra/pico-search';
import FlowRow from './FlowRow.vue';
import FlowTemplatesGallery from './FlowTemplatesGallery.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { BaseTable } from 'dashboard/components-next/table';
import AutomationRuleRow from './AutomationRuleRow.vue';
import EditAutomationRule from './EditAutomationRule.vue';

const getters = useStoreGetters();
const store = useStore();
const router = useRouter();
const { t } = useI18n();
const confirmDialog = ref(null);

const loading = ref({});
const addDialogRef = ref(null);
const showDeleteConfirmationPopup = ref(false);
const showTemplatesGallery = ref(false);
const selectedFlow = ref({});
const editDialogRef = ref(null);
const selectedAutomation = ref({});
const searchQuery = ref('');
const importing = ref(false);
const toggleModalTitle = ref(t('AUTOMATION.TOGGLE.ACTIVATION_TITLE'));
const toggleModalDescription = ref(
  t('AUTOMATION.TOGGLE.ACTIVATION_DESCRIPTION')
);

// A tela agora lista FLOWS (o motor unificado), não mais AutomationRules.
const records = computed(() => getters['flows/getFlows'].value);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;
  return picoSearch(records.value, query, ['name', 'description']);
});

// Automações do MODO ANTIGO (automation_rules): reexibidas para ver / ligar-desligar / editar /
// excluir. Aditivo — não altera as flows. A migração pro canvas é o botão "Importar" (BackfillService).
const legacyRules = computed(() => getters['automations/getAutomations'].value);
const filteredLegacyRules = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return legacyRules.value;
  return picoSearch(legacyRules.value, query, ['name', 'description']);
});
const legacyHeaders = computed(() => [
  t('AUTOMATION.LIST.TABLE_HEADER.NAME'),
  t('AUTOMATION.LIST.TABLE_HEADER.ACTIVE'),
  t('AUTOMATION.LIST.TABLE_HEADER.CREATED_ON'),
  t('AUTOMATION.LIST.TABLE_HEADER.ACTIONS'),
]);
const uiFlags = computed(() => getters['flows/getUIFlags'].value);
const accountId = computed(() => getters.getCurrentAccountId.value);

const deleteConfirmText = computed(
  () => `${t('AUTOMATION.DELETE.CONFIRM.YES')} ${selectedFlow.value.name}`
);

const deleteRejectText = computed(
  () => `${t('AUTOMATION.DELETE.CONFIRM.NO')} ${selectedFlow.value.name}`
);

const deleteMessage = computed(() => ` ${selectedFlow.value.name}?`);

const isSLAEnabled = computed(() =>
  getters['accounts/isFeatureEnabledonAccount'].value(accountId.value, 'sla')
);

onMounted(() => {
  store.dispatch('inboxes/get');
  store.dispatch('agents/get');
  store.dispatch('contacts/get');
  store.dispatch('teams/get');
  store.dispatch('labels/get');
  store.dispatch('campaigns/get');
  store.dispatch('flows/get');
  store.dispatch('automations/get');
  if (isSLAEnabled.value) {
    store.dispatch('sla/get');
  }
});

const openCanvas = () => {
  router.push({
    name: 'automation_canvas_new',
    params: { accountId: accountId.value },
  });
};

// Galeria de modelos: abre o overlay; escolher um modelo semeia o canvas via ?templateKey
// (o FlowCanvasView monta a definition — NADA é gravado até o usuário salvar). `null` = começar
// do zero (mesmo destino que "Novo fluxo"). Ver flowTemplates.js / FlowCanvasView#seedFromTemplate.
const openTemplatesGallery = () => {
  showTemplatesGallery.value = true;
};
const onSelectTemplate = template => {
  showTemplatesGallery.value = false;
  router.push({
    name: 'automation_canvas_new',
    params: { accountId: accountId.value },
    query: template ? { templateKey: template.key } : {},
  });
};

// Editar um Flow = abrir o canvas (a `definition` é a fonte da verdade; não há form aqui).
const openFlowCanvas = flow => {
  router.push({
    name: 'automation_canvas_edit',
    params: { accountId: accountId.value, flowId: flow.id },
  });
};

// Form CLÁSSICO (AutomationRule) — mantido funcional atrás do botão "avançado". Cria uma
// regra no motor legado; ela não aparece nesta lista (que mostra Flows) até ser importada.
const openAddPopup = () => {
  addDialogRef.value?.open();
};
const hideAddPopup = () => {
  addDialogRef.value?.close();
};

const openDeletePopup = flow => {
  showDeleteConfirmationPopup.value = true;
  selectedFlow.value = flow;
};
const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const deleteFlow = async id => {
  try {
    await store.dispatch('flows/delete', id);
    useAlert(t('AUTOMATION.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('AUTOMATION.DELETE.API.ERROR_MESSAGE'));
  } finally {
    loading.value[selectedFlow.value.id] = false;
  }
};
const confirmDeletion = () => {
  loading.value[selectedFlow.value.id] = true;
  closeDeletePopup();
  deleteFlow(selectedFlow.value.id);
};

// Criar (add) ou editar (edit) uma regra clássica — mesmo handler dos dois dialogs (Add/Edit).
const submitAutomation = async (payload, mode) => {
  try {
    const action =
      mode === 'edit' ? 'automations/update' : 'automations/create';
    await store.dispatch(action, payload);
    useAlert(
      mode === 'edit'
        ? t('AUTOMATION.EDIT.API.SUCCESS_MESSAGE')
        : t('AUTOMATION.ADD.API.SUCCESS_MESSAGE')
    );
    hideAddPopup();
    editDialogRef.value?.close();
  } catch (error) {
    useAlert(
      mode === 'edit'
        ? t('AUTOMATION.EDIT.API.ERROR_MESSAGE')
        : t('AUTOMATION.ADD.API.ERROR_MESSAGE')
    );
  }
};

// --- Gerência das regras do MODO ANTIGO (reaproveita a store 'automations' + handlers legados) ---
const openEditPopup = rule => {
  selectedAutomation.value = { ...rule };
  editDialogRef.value?.open();
};

// Liga/desliga uma regra antiga — PERSISTE (PATCH automation_rules/:id) e reflete após reload;
// desligar faz a regra PARAR de disparar no backend. Reusa o confirmDialog + vocabulário TOGGLE.
const toggleAutomation = async ({ id, name, status }) => {
  try {
    toggleModalTitle.value = status
      ? t('AUTOMATION.TOGGLE.DEACTIVATION_TITLE')
      : t('AUTOMATION.TOGGLE.ACTIVATION_TITLE');
    toggleModalDescription.value = status
      ? t('AUTOMATION.TOGGLE.DEACTIVATION_DESCRIPTION', {
          automationName: name,
        })
      : t('AUTOMATION.TOGGLE.ACTIVATION_DESCRIPTION', { automationName: name });
    const ok = await confirmDialog.value.showConfirmation();
    if (ok) {
      await store.dispatch('automations/update', { id, active: !status });
      useAlert(
        status
          ? t('AUTOMATION.TOGGLE.DEACTIVATION_SUCCESFUL')
          : t('AUTOMATION.TOGGLE.ACTIVATION_SUCCESFUL')
      );
    }
  } catch (error) {
    useAlert(t('AUTOMATION.EDIT.API.ERROR_MESSAGE'));
  }
};

const cloneAutomation = async ({ id }) => {
  try {
    await store.dispatch('automations/clone', id);
    useAlert(t('AUTOMATION.CLONE.API.SUCCESS_MESSAGE'));
    store.dispatch('automations/get');
  } catch (error) {
    useAlert(t('AUTOMATION.CLONE.API.ERROR_MESSAGE'));
  }
};

const deleteAutomation = async rule => {
  toggleModalTitle.value = t('LABEL_MGMT.DELETE.CONFIRM.TITLE');
  toggleModalDescription.value = `${t('AUTOMATION.DELETE.CONFIRM.MESSAGE')} ${rule.name}?`;
  try {
    const ok = await confirmDialog.value.showConfirmation();
    if (ok) {
      await store.dispatch('automations/delete', rule.id);
      useAlert(t('AUTOMATION.DELETE.API.SUCCESS_MESSAGE'));
    }
  } catch (error) {
    useAlert(t('AUTOMATION.DELETE.API.ERROR_MESSAGE'));
  }
};

const toggleFlow = async ({ id, name, status }) => {
  try {
    if (status) {
      toggleModalTitle.value = t('AUTOMATION.TOGGLE.DEACTIVATION_TITLE');
      toggleModalDescription.value = t(
        'AUTOMATION.TOGGLE.DEACTIVATION_DESCRIPTION',
        {
          automationName: name,
        }
      );
    } else {
      toggleModalTitle.value = t('AUTOMATION.TOGGLE.ACTIVATION_TITLE');
      toggleModalDescription.value = t(
        'AUTOMATION.TOGGLE.ACTIVATION_DESCRIPTION',
        {
          automationName: name,
        }
      );
    }

    const ok = await confirmDialog.value.showConfirmation();
    if (ok) {
      await store.dispatch('flows/update', {
        id: id,
        active: !status,
      });
      const message = status
        ? t('AUTOMATION.TOGGLE.DEACTIVATION_SUCCESFUL')
        : t('AUTOMATION.TOGGLE.ACTIVATION_SUCCESFUL');
      useAlert(message);
    }
  } catch (error) {
    useAlert(t('AUTOMATION.EDIT.API.ERROR_MESSAGE'));
  }
};

// Importa Macros + AutomationRules existentes como Flows equivalentes (cada uma vira um Flow
// LINEAR) via o endpoint POST flows/import, que roda o Flows::BackfillService no servidor
// (idempotente por trigger_config.backfill_source). O store recarrega a lista ao concluir; aqui
// só traduzimos o `summary` no feedback (criados / falhas / nada a importar).
const importLegacy = async () => {
  importing.value = true;
  try {
    const { summary } = await store.dispatch('flows/importLegacy', {});
    const created = (summary?.macros || 0) + (summary?.automation_rules || 0);
    const failed = (summary?.errors || []).length;

    if (!created && !failed) {
      useAlert(t('AUTOMATION.IMPORT.NOTHING'));
    } else if (failed && created) {
      useAlert(t('AUTOMATION.IMPORT.PARTIAL', { created, failed }));
    } else if (failed) {
      useAlert(t('AUTOMATION.IMPORT.ERROR'));
    } else {
      useAlert(t('AUTOMATION.IMPORT.SUCCESS', { created }));
    }
  } catch (error) {
    useAlert(t('AUTOMATION.IMPORT.ERROR'));
  } finally {
    importing.value = false;
  }
};

const tableHeaders = computed(() => {
  return [
    t('AUTOMATION.LIST.TABLE_HEADER.NAME'),
    t('AUTOMATION.LIST.TABLE_HEADER.TYPE'),
    t('AUTOMATION.LIST.TABLE_HEADER.ACTIVE'),
    t('AUTOMATION.LIST.TABLE_HEADER.ACTIONS'),
  ];
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('AUTOMATION.LOADING')"
    :no-records-found="!records.length && !legacyRules.length"
    :no-records-message="$t('AUTOMATION.LIST.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('AUTOMATION.HEADER')"
        :description="$t('AUTOMATION.DESCRIPTION')"
        :link-text="$t('AUTOMATION.LEARN_MORE')"
        :search-placeholder="$t('AUTOMATION.SEARCH_PLACEHOLDER')"
        feature-name="automation"
      >
        <template v-if="records?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('AUTOMATION.COUNT', { n: records.length }) }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="$t('AUTOMATION.CLASSIC_RULE_BTN')"
            size="sm"
            variant="link"
            color="slate"
            data-testid="create-classic-rule"
            @click="openAddPopup"
          />
          <Button
            :label="$t('AUTOMATION.IMPORT.BUTTON')"
            size="sm"
            variant="faded"
            icon="i-lucide-download"
            :is-loading="importing"
            data-testid="import-legacy"
            @click="importLegacy"
          />
          <Button
            :label="$t('AUTOMATION.TEMPLATES.BUTTON')"
            size="sm"
            variant="faded"
            icon="i-lucide-layout-grid"
            data-testid="open-templates"
            @click="openTemplatesGallery"
          />
          <Button
            :label="$t('AUTOMATION.CANVAS.NEW_FLOW')"
            size="sm"
            icon="i-lucide-workflow"
            data-testid="open-canvas"
            @click="openCanvas"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <BaseTable
        v-if="records.length"
        :headers="tableHeaders"
        :items="filteredRecords"
        :no-data-message="
          searchQuery
            ? $t('AUTOMATION.NO_RESULTS')
            : $t('AUTOMATION.LIST.EMPTY')
        "
      >
        <template #row="{ items }">
          <FlowRow
            v-for="flow in items"
            :key="flow.id"
            :flow="flow"
            :loading="loading[flow.id]"
            @toggle="toggleFlow"
            @edit="openFlowCanvas"
            @delete="openDeletePopup"
          />
        </template>
      </BaseTable>

      <!-- Automações do MODO ANTIGO (automation_rules) — só quando houver ao menos uma regra -->
      <div v-if="legacyRules.length" :class="records.length ? 'mt-8' : ''">
        <div class="mb-3">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ $t('AUTOMATION.LEGACY.TITLE') }}
          </h3>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ $t('AUTOMATION.LEGACY.HELP') }}
          </p>
        </div>
        <BaseTable
          :headers="legacyHeaders"
          :items="filteredLegacyRules"
          :no-data-message="$t('AUTOMATION.NO_RESULTS')"
        >
          <template #row="{ items }">
            <AutomationRuleRow
              v-for="rule in items"
              :key="rule.id"
              :automation="rule"
              :loading="loading[rule.id]"
              @toggle="toggleAutomation"
              @edit="openEditPopup"
              @delete="deleteAutomation"
              @clone="cloneAutomation"
            />
          </template>
        </BaseTable>
      </div>
    </template>

    <FlowTemplatesGallery
      v-if="showTemplatesGallery"
      @close="showTemplatesGallery = false"
      @select="onSelectTemplate"
    />

    <AddAutomationRule ref="addDialogRef" @save-automation="submitAutomation" />

    <EditAutomationRule
      ref="editDialogRef"
      :selected-response="selectedAutomation"
      @save-automation="submitAutomation"
    />

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('LABEL_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('AUTOMATION.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
    />

    <woot-confirm-modal
      ref="confirmDialog"
      :title="toggleModalTitle"
      :description="toggleModalDescription"
    />
  </SettingsLayout>
</template>
