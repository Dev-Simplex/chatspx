<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import BaseTableRow from 'dashboard/components-next/table/BaseTableRow.vue';
import BaseTableCell from 'dashboard/components-next/table/BaseTableCell.vue';

/**
 * Lista de agentes de UM isolamento de caixa de entrada, no mesmo desenho da
 * seleção de agentes de um time (`settings/teams/AgentSelector.vue`): tabela,
 * avatar, "selecionar todos" e contador. Não dá para reusar aquele componente
 * direto porque ele carrega o botão de submit do formulário de time — aqui quem
 * salva é o "Atualizar configurações" da tela de configurações da caixa.
 *
 * A tela fala PARTICIPANTES (quem É isolado); o banco guarda EXCEÇÕES. A
 * inversão acontece no submit do controller, não aqui — ver
 * InboxIsolationExemption.
 */
const props = defineProps({
  // Membros da caixa, no formato do partial `api/v1/models/_agent` (role e
  // supervised_team_ids inclusos).
  agents: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

// `null` = a caixa ainda não disse quem participa (payload antigo em cache, por
// exemplo). Nesse caso a tela mostra TODO MUNDO marcado — o comportamento de
// hoje — e a tela de configurações não manda a chave no submit. Lista VAZIA é
// diferente: é a escolha explícita de isentar todo mundo.
const modelValue = defineModel({ type: Array, default: null });

const store = useStore();
const { t } = useI18n();

const teams = computed(() => store.getters['teams/getTeams']);

const isAdministrator = agent => agent.role === 'administrator';
const isSupervisor = agent => (agent.supervised_team_ids || []).length > 0;

// Administrador fica FORA da tabela: ele já é isento das duas regras e a caixinha
// sugeriria que dá para isolá-lo. Quem explica isso é a nota abaixo da tabela.
const candidates = computed(() =>
  props.agents.filter(a => !isAdministrator(a))
);

const selectableAgents = computed(() =>
  candidates.value.filter(agent => !isSupervisor(agent))
);
const supervisorAgents = computed(() => candidates.value.filter(isSupervisor));

// Supervisores no fim da lista: eles não decidem nada, só aparecem para explicar
// por que não estão isolados.
const listedAgents = computed(() => [
  ...selectableAgents.value,
  ...supervisorAgents.value,
]);

const participantIds = computed(() =>
  modelValue.value === null
    ? selectableAgents.value.map(a => a.id)
    : modelValue.value
);

const isSelected = id => participantIds.value.includes(id);

const selectedIds = computed(() =>
  selectableAgents.value.filter(agent => isSelected(agent.id)).map(a => a.id)
);

// O total conta TODA a lista, supervisor incluso: "4 de 6" responde quantos
// agentes daquela caixa seguem isolados, e o supervisor não segue.
const selectedCount = computed(() => selectedIds.value.length);

const allSelected = computed(
  () =>
    selectableAgents.value.length > 0 &&
    selectedCount.value === selectableAgents.value.length
);
const someSelected = computed(
  () => selectedCount.value > 0 && !allSelected.value
);

/**
 * O supervisor de time NUNCA vira exceção por esta tela. A isenção dele é por
 * TIME (TeamSupervision) e gravar uma linha aqui a esticaria para a caixa
 * inteira — dois mecanismos diferentes que convivem. Por isso ele sobe sempre
 * como participante, mesmo aparecendo sem caixa de seleção.
 */
const updateParticipants = ids => {
  modelValue.value = [...ids, ...supervisorAgents.value.map(a => a.id)];
};

const toggleAgent = id => {
  updateParticipants(
    isSelected(id)
      ? selectedIds.value.filter(item => item !== id)
      : [...selectedIds.value, id]
  );
};

const toggleSelectAll = () => {
  updateParticipants(
    allSelected.value ? [] : selectableAgents.value.map(a => a.id)
  );
};

const teamNamesOf = agent =>
  (agent.supervised_team_ids || [])
    .map(id => teams.value.find(team => team.id === id)?.name)
    .filter(Boolean);

// Para o supervisor, o time supervisionado diz mais do que o e-mail.
const secondaryLabel = agent => {
  const names = teamNamesOf(agent);
  if (names.length === 1) {
    return t('INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.SUPERVISOR_OF', {
      name: names[0],
    });
  }
  if (names.length > 1) {
    return t(
      'INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.SUPERVISOR_OF_MANY',
      { count: names.length }
    );
  }
  return agent.email || '--';
};

const isParticipating = agent => !isSupervisor(agent) && isSelected(agent.id);

const headers = computed(() => [
  '',
  t('INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.SELECT_ALL'),
  '',
]);
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <span class="text-heading-3 text-n-slate-12">
        {{ $t('INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.TITLE') }}
      </span>
      <span
        v-if="listedAgents.length"
        class="text-sm tabular-nums text-n-slate-10"
      >
        {{
          $t('INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.COUNT', {
            selected: selectedCount,
            total: listedAgents.length,
          })
        }}
      </span>
    </div>

    <div class="overflow-hidden border rounded-lg border-n-weak">
      <BaseTable
        :headers="headers"
        :items="listedAgents"
        :no-data-message="
          isLoading
            ? $t('INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.LOADING')
            : $t('INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.EMPTY')
        "
      >
        <template #header-0>
          <div class="flex items-center">
            <Checkbox
              :model-value="allSelected"
              :indeterminate="someSelected"
              :disabled="!selectableAgents.length"
              @change="toggleSelectAll"
            />
          </div>
        </template>

        <template #row="{ items }">
          <BaseTableRow v-for="agent in items" :key="agent.id" :item="agent">
            <template #default>
              <BaseTableCell class="w-5">
                <div class="flex items-center size-4">
                  <Checkbox
                    v-if="!isSupervisor(agent)"
                    :model-value="isSelected(agent.id)"
                    @change="() => toggleAgent(agent.id)"
                  />
                </div>
              </BaseTableCell>

              <BaseTableCell class="min-w-0">
                <div
                  class="flex items-center min-w-0 gap-2"
                  :class="{ 'opacity-60': !isParticipating(agent) }"
                >
                  <Avatar
                    :src="agent.thumbnail"
                    :name="agent.name"
                    :size="24"
                    rounded-full
                    class="flex-shrink-0"
                  />
                  <div class="min-w-0">
                    <h4 class="mb-0 truncate text-heading-3 text-n-slate-12">
                      {{ agent.name }}
                    </h4>
                    <span class="block text-xs truncate text-n-slate-10">
                      {{ secondaryLabel(agent) }}
                    </span>
                  </div>
                </div>
              </BaseTableCell>

              <BaseTableCell align="end">
                <span
                  v-if="isSupervisor(agent)"
                  class="inline-block px-2 py-0.5 text-xs rounded-md whitespace-nowrap bg-n-slate-3 text-n-slate-11"
                >
                  {{
                    $t(
                      'INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.ALWAYS_EXEMPT'
                    )
                  }}
                </span>
                <span
                  v-else-if="!isSelected(agent.id)"
                  class="inline-block px-2 py-0.5 text-xs rounded-md whitespace-nowrap bg-n-amber-3 text-n-amber-11"
                >
                  {{
                    $t(
                      'INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.SEES_EVERYTHING'
                    )
                  }}
                </span>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>

    <p class="mb-0 text-sm text-n-slate-10">
      {{ $t('INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.ADMIN_NOTE') }}
      <template v-if="supervisorAgents.length">
        {{
          $t('INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.SUPERVISOR_NOTE')
        }}
      </template>
    </p>
  </div>
</template>
