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
import Button from 'dashboard/components-next/button/Button.vue';
import { BaseTable } from 'dashboard/components-next/table';

const getters = useStoreGetters();
const store = useStore();
const router = useRouter();
const { t } = useI18n();
const confirmDialog = ref(null);

const loading = ref({});
const addDialogRef = ref(null);
const showDeleteConfirmationPopup = ref(false);
const selectedFlow = ref({});
const searchQuery = ref('');
const importing = ref(false);
const toggleModalTitle = ref(t('AUTOMATION.TOGGLE.ACTIVATION_TITLE'));
const toggleModalDescription = ref(
  t('AUTOMATION.TOGGLE.ACTIVATION_DESCRIPTION')
);

// A tela agora lista FLOWS (o motor unificado), não mais AutomationRules.
const records = computed(() => getters['flows/getFlows'].value);
// Fontes legadas — só usadas pela ação "Importar automações e macros".
const macros = computed(() => getters['macros/getMacros'].value);
const automations = computed(() => getters['automations/getAutomations'].value);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;
  return picoSearch(records.value, query, ['name', 'description']);
});
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
  // Carregadas para a ação de importar e para o form clássico (avançado).
  store.dispatch('automations/get');
  store.dispatch('macros/get');
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

// Criar regra clássica (motor legado) — só via o form avançado.
const submitAutomation = async payload => {
  try {
    await store.dispatch('automations/create', payload);
    useAlert(t('AUTOMATION.ADD.API.SUCCESS_MESSAGE'));
    hideAddPopup();
  } catch (error) {
    useAlert(t('AUTOMATION.ADD.API.ERROR_MESSAGE'));
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

// Cada ação (na ordem) vira um nó `action`; as arestas encadeiam linearmente. Espelha
// `Flows::BackfillService#actions_to_definition` (backfill_service.rb) — mantido em paridade.
const actionsToDefinition = actions => {
  const nodes = (actions || []).map((action, index) => ({
    id: `n${index + 1}`,
    type: 'action',
    action_name: action.action_name,
    action_params: action.action_params,
  }));
  const edges = nodes
    .slice(1)
    .map((node, index) => ({ from: nodes[index].id, to: node.id }));
  return { nodes, edges };
};

// Idempotência: um Flow importado carrega `trigger_config.backfill_source` ("macro:<id>" /
// "automation_rule:<id>"). Reimportar só cria o que ainda falta — igual ao BackfillService.
const backfilledSources = () => {
  const done = new Set();
  records.value.forEach(flow => {
    const src = flow?.trigger_config?.backfill_source;
    if (src) done.add(src);
  });
  return done;
};

// Importa Macros + AutomationRules existentes como Flows equivalentes (cada uma vira um Flow
// LINEAR). TODO: quando a fatia de backend expuser um endpoint de backfill (rake flows:backfill
// já existe em CLI), trocar este espelho client-side por uma chamada única a esse endpoint.
const importLegacy = async () => {
  importing.value = true;
  try {
    // Garante fontes frescas antes de calcular o que falta importar.
    await Promise.all([
      store.dispatch('automations/get'),
      store.dispatch('macros/get'),
      store.dispatch('flows/get'),
    ]);

    const done = backfilledSources();
    const jobs = [];

    macros.value.forEach(macro => {
      const source = `macro:${macro.id}`;
      if (done.has(source)) return;
      jobs.push({
        name: macro.name,
        trigger_type: 'manual',
        trigger_config: { backfill_source: source },
        definition: actionsToDefinition(macro.actions),
        visibility: macro.visibility || 'global',
        active: true,
      });
    });

    automations.value.forEach(rule => {
      const source = `automation_rule:${rule.id}`;
      if (done.has(source)) return;
      jobs.push({
        name: rule.name,
        description: rule.description,
        trigger_type: 'conversation_event',
        trigger_config: {
          event_name: rule.event_name,
          conditions: rule.conditions,
          backfill_source: source,
        },
        definition: actionsToDefinition(rule.actions),
        visibility: 'global',
        active: rule.active,
      });
    });

    if (!jobs.length) {
      useAlert(t('AUTOMATION.IMPORT.NOTHING'));
      return;
    }

    const results = await Promise.allSettled(
      jobs.map(job => store.dispatch('flows/create', job))
    );
    const created = results.filter(r => r.status === 'fulfilled').length;
    const failed = results.length - created;

    // Reconcilia com a verdade do servidor (nomes/definições normalizados).
    await store.dispatch('flows/get');

    if (failed && created) {
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
    :no-records-found="!records.length"
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
    </template>

    <AddAutomationRule ref="addDialogRef" @save-automation="submitAutomation" />

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
