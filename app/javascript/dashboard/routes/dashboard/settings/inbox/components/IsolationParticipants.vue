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
  // Qual das duas regras este card configura. Os dois isolamentos NÃO isentam a mesma
  // gente, então o texto (e o realce) da tabela precisam saber de qual se trata:
  // - 'agent_message': administrador e supervisor de time são isentos;
  // - 'team_message': NINGUÉM é isento por natureza — nem administrador, nem supervisor.
  //   O filtro por time sempre valeu para todo mundo e a saída sempre foi desligar a
  //   chave da caixa (ver TeamMessageIsolation, no backend).
  isolationType: {
    type: String,
    default: 'agent_message',
    validator: value => ['agent_message', 'team_message'].includes(value),
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

const isTeamIsolation = computed(() => props.isolationType === 'team_message');

const isAdministrator = agent => agent.role === 'administrator';
const isSupervisor = agent => (agent.supervised_team_ids || []).length > 0;

// Administrador fica FORA da tabela: nas duas regras ele não é isentável por esta tela
// — no isolamento por agente porque já é isento, no de time porque a única saída é
// desligar a chave da caixa. A caixinha sugeriria que dá para escolher, e não dá. Quem
// explica isso é a nota abaixo da tabela, que muda conforme o card.
const candidates = computed(() =>
  props.agents.filter(a => !isAdministrator(a))
);

const selectableAgents = computed(() =>
  candidates.value.filter(agent => !isSupervisor(agent))
);
const supervisorAgents = computed(() => candidates.value.filter(isSupervisor));

// Supervisores no fim da lista: eles não decidem nada aqui, só aparecem para explicar
// por que estão fora da escolha.
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

// Base do "selecionar todos": só quem TEM caixinha entra na conta.
const selectedCount = computed(() => selectedIds.value.length);

// O que o contador mostra: quantos agentes daquela caixa seguem isolados, sobre a lista
// inteira. O supervisor conta conforme a regra deste card — no de time ele segue isolado
// como qualquer um, no de agente ele é isento nas conversas do time que supervisiona.
const isolatedCount = computed(() =>
  isTeamIsolation.value
    ? selectedCount.value + supervisorAgents.value.length
    : selectedCount.value
);

const allSelected = computed(
  () =>
    selectableAgents.value.length > 0 &&
    selectedCount.value === selectableAgents.value.length
);
const someSelected = computed(
  () => selectedCount.value > 0 && !allSelected.value
);

/**
 * O supervisor de time NUNCA vira exceção por esta tela, nos DOIS cards, mas por
 * motivos diferentes — e é por isso que o texto da linha dele muda:
 *
 * - isolamento por AGENTE: ele já é isento pela supervisão (TeamSupervision), só que
 *   apenas nas conversas do time que supervisiona. Gravar uma exceção aqui esticaria
 *   essa isenção para a caixa inteira: são dois mecanismos que convivem.
 * - isolamento por TIME: a supervisão NÃO isenta. Ele participa como qualquer agente,
 *   e continua sem caixinha porque poder desmarcá-lo é outra decisão, ainda não tomada.
 *
 * Nos dois casos ele sobe sempre como participante — a lista salva não muda.
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

// Linha esmaecida = quem NÃO está sujeito ao isolamento DESTE card. O supervisor esmaece
// só no de agente; no de time ele está sujeito como todo mundo.
const isParticipating = agent =>
  isSupervisor(agent) ? isTeamIsolation.value : isSelected(agent.id);

// Os três textos que MENTIRIAM se fossem um só para os dois cards: o administrador não
// escapa do isolamento de time, e o supervisor tampouco. As chaves vão literais (e não
// montadas com o tipo) para o linter de i18n continuar enxergando quem usa o quê.
const supervisorBadge = computed(() =>
  isTeamIsolation.value
    ? t(
        'INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.SUPERVISOR_BADGE_TEAM'
      )
    : t(
        'INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.SUPERVISOR_BADGE_AGENT'
      )
);
const adminNote = computed(() =>
  isTeamIsolation.value
    ? t('INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.ADMIN_NOTE_TEAM')
    : t('INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.ADMIN_NOTE_AGENT')
);
const supervisorNote = computed(() =>
  isTeamIsolation.value
    ? t('INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.SUPERVISOR_NOTE_TEAM')
    : t(
        'INBOX_MGMT.SETTINGS_POPUP.ISOLATION_PARTICIPANTS.SUPERVISOR_NOTE_AGENT'
      )
);

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
            selected: isolatedCount,
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
                  {{ supervisorBadge }}
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
      {{ adminNote }}
      <template v-if="supervisorAgents.length">
        {{ supervisorNote }}
      </template>
    </p>
  </div>
</template>
