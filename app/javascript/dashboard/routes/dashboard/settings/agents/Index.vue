<script setup>
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { computed, onMounted, ref } from 'vue';
import Avatar from 'next/avatar/Avatar.vue';
import { useI18n } from 'vue-i18n';
import { picoSearch } from '@scmmishra/pico-search';
import {
  useStoreGetters,
  useStore,
  useMapGetter,
} from 'dashboard/composables/store';

import AddAgent from './AddAgent.vue';
import EditAgent from './EditAgent.vue';
import AIAgentsSection from './AIAgentsSection.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();

// Quem chega aqui sem ser admin só pode ter entrado pela permissão
// `team_supervisor` (ver agent.routes.js). Aqui reduzimos os poderes (nada de
// convidar nem excluir agente) e recortamos a lista para os times supervisionados.
const isSupervisorView = computed(() => !isAdmin.value);

const loading = ref({});
const showAddPopup = ref(false);
const showDeletePopup = ref(false);
const showEditPopup = ref(false);
const agentAPI = ref({ message: '' });
const currentAgent = ref({});
const searchQuery = ref('');

const deleteConfirmText = computed(
  () => `${t('AGENT_MGMT.DELETE.CONFIRM.YES')} ${currentAgent.value.name}`
);
const deleteRejectText = computed(() => {
  return `${t('AGENT_MGMT.DELETE.CONFIRM.NO')} ${currentAgent.value.name}`;
});
const deleteMessage = computed(() => {
  return ` ${currentAgent.value.name}?`;
});

const allAgents = computed(() => getters['agents/getAgents'].value);
const supervisedTeams = useMapGetter('teams/getSupervisedTeams');

// T4: o recorte "só os agentes dos meus times" é DESTA TELA, não da API.
// `GET /agents` devolve a conta inteira de propósito: a mesma resposta alimenta a
// store `agents` do dashboard inteiro (menções do chat interno, participantes da
// conversa, Kanban, filtro de responsável da lista). Recortar lá tirava gente
// dessas telas e, no caso de supervisionar um time sem membros, deixava o
// supervisor sem agente nenhum em lugar nenhum.
const agentList = computed(() => {
  if (!isSupervisorView.value) return allAgents.value;

  const supervisedIds = new Set(supervisedTeams.value.map(({ id }) => id));
  if (!supervisedIds.size) return [];

  // supervisionar ≠ ser membro: cruzamos com os times de que o agente É MEMBRO
  return allAgents.value.filter(agent =>
    (agent.team_ids || []).some(id => supervisedIds.has(id))
  );
});

const filteredAgentList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return agentList.value;
  return picoSearch(agentList.value, query, ['name', 'email']);
});

const agentsUiFlags = computed(() => getters['agents/getUIFlags'].value);
const teamsUiFlags = computed(() => getters['teams/getUIFlags'].value);

// No modo supervisor o recorte depende dos TIMES: enquanto eles não chegam a lista
// filtrada é legitimamente vazia, e sem esperar por eles a tela pisca o
// "não há agentes nos times que você supervisiona" antes de mostrar quem existe.
const uiFlags = computed(() => ({
  ...agentsUiFlags.value,
  isFetching:
    agentsUiFlags.value.isFetching ||
    (isSupervisorView.value && teamsUiFlags.value.isFetching),
}));
const currentUserId = computed(() => getters.getCurrentUserID.value);
const customRoles = useMapGetter('customRole/getCustomRoles');
const teams = useMapGetter('teams/getTeams');

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('customRole/getCustomRole');
  // os times alimentam o chip de supervisor e o campo do modal de edição
  store.dispatch('teams/get');
});

// supervisionar ≠ ser membro: a lista vem separada de team_ids
const isSupervisor = agent => !!agent.supervised_team_ids?.length;

const supervisedTeamNames = agent =>
  (agent.supervised_team_ids || [])
    .map(id => teams.value.find(team => team.id === id)?.name)
    .filter(Boolean)
    .join(', ');

const findCustomRole = agent =>
  customRoles.value.find(role => role.id === agent.custom_role_id);

const getAgentRoleName = agent => {
  if (!agent.custom_role_id) {
    return t(`AGENT_MGMT.AGENT_TYPES.${agent.role.toUpperCase()}`);
  }
  const customRole = findCustomRole(agent);
  return customRole ? customRole.name : '';
};

const getAgentRolePermissions = agent => {
  if (!agent.custom_role_id) {
    return [];
  }
  const customRole = findCustomRole(agent);
  return customRole?.permissions || [];
};

const verifiedAdministrators = computed(() => {
  return agentList.value.filter(
    agent => agent.role === 'administrator' && agent.confirmed
  );
});

const showEditAction = agent => {
  if (currentUserId.value === agent.id) return false;

  // O backend recusa (401) um supervisor editando um administrador. Sem esconder
  // o botão aqui, o admin aparece na lista — ele é membro do time — e o
  // supervisor cai num beco: abre o modal, renomeia e só descobre no erro.
  if (isSupervisorView.value && agent.role === 'administrator') return false;

  return true;
};

const showDeleteAction = agent => {
  // excluir agente da conta é ação de admin — supervisor só renomeia
  if (isSupervisorView.value) {
    return false;
  }

  if (currentUserId.value === agent.id) {
    return false;
  }

  if (!agent.confirmed) {
    return true;
  }

  if (agent.role === 'administrator') {
    return verifiedAdministrators.value.length !== 1;
  }
  return true;
};

const showAlertMessage = message => {
  loading.value[currentAgent.value.id] = false;
  currentAgent.value = {};
  agentAPI.value.message = message;
  useAlert(message);
};

const openAddPopup = () => {
  showAddPopup.value = true;
};
const hideAddPopup = () => {
  showAddPopup.value = false;
};

const openEditPopup = agent => {
  showEditPopup.value = true;
  currentAgent.value = agent;
};
const hideEditPopup = () => {
  showEditPopup.value = false;
};

const openDeletePopup = agent => {
  showDeletePopup.value = true;
  currentAgent.value = agent;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};

const deleteAgent = async id => {
  try {
    await store.dispatch('agents/delete', id);
    showAlertMessage(t('AGENT_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    showAlertMessage(t('AGENT_MGMT.DELETE.API.ERROR_MESSAGE'));
  }
};
const confirmDeletion = () => {
  loading.value[currentAgent.value.id] = true;
  closeDeletePopup();
  deleteAgent(currentAgent.value.id);
};
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('AGENT_MGMT.LOADING')"
    :no-records-found="!agentList.length"
    :no-records-message="
      isSupervisorView
        ? $t('AGENT_MGMT.LIST.404_SUPERVISOR')
        : $t('AGENT_MGMT.LIST.404')
    "
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="
          isSupervisorView
            ? $t('AGENT_MGMT.HEADER_SUPERVISOR')
            : $t('AGENT_MGMT.HEADER')
        "
        :description="
          isSupervisorView
            ? $t('AGENT_MGMT.DESCRIPTION_SUPERVISOR')
            : $t('AGENT_MGMT.DESCRIPTION')
        "
        :link-text="$t('AGENT_MGMT.LEARN_MORE')"
        :search-placeholder="$t('AGENT_MGMT.SEARCH_PLACEHOLDER')"
        feature-name="agents"
      >
        <template v-if="agentList?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('AGENT_MGMT.COUNT', { n: agentList.length }) }}
          </span>
        </template>
        <template #actions>
          <Button
            v-if="!isSupervisorView"
            :label="$t('AGENT_MGMT.HEADER_BTN_TXT')"
            size="sm"
            @click="openAddPopup"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <span
        v-if="!filteredAgentList.length && searchQuery"
        class="flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
      >
        {{ $t('AGENT_MGMT.NO_RESULTS') }}
      </span>
      <div
        v-else
        class="divide-y divide-n-weak border border-n-weak rounded-xl"
      >
        <div
          v-for="(agent, index) in filteredAgentList"
          :key="agent.email"
          class="flex justify-between flex-row items-start gap-4 px-4 py-4"
        >
          <div class="flex items-center gap-4">
            <Avatar
              :src="agent.thumbnail"
              :name="agent.name"
              :status="agent.availability_status"
              :size="40"
              hide-offline-status
            />
            <div class="flex flex-col gap-1.5 items-start">
              <span class="block text-heading-3 text-n-slate-12 capitalize">
                {{ agent.name }}
              </span>
              <div class="flex items-center gap-2">
                <span class="text-body-main text-n-slate-11">
                  {{ agent.email }}
                </span>
                <div class="w-px h-3 bg-n-strong rounded-lg" />
                <span
                  class="block w-fit text-body-main text-n-slate-11 relative"
                  :class="{
                    'hover:text-n-slate-12 group cursor-pointer':
                      agent.custom_role_id,
                  }"
                >
                  {{ getAgentRoleName(agent) }}

                  <div
                    class="absolute ltr:left-0 rtl:right-0 z-10 hidden w-[300px] bg-n-solid-1 dark:bg-[#233138] rounded-lg border border-[var(--wa-list-border)] dark:border-[var(--wa-list-border-dark)] shadow-[0_2px_8px_rgba(11,20,26,0.12)] top-14 md:top-12"
                    :class="{ 'group-hover:block': agent.custom_role_id }"
                  >
                    <div class="flex flex-col gap-1 p-4">
                      <span class="text-heading-3 text-n-slate-12">
                        {{ $t('AGENT_MGMT.LIST.AVAILABLE_CUSTOM_ROLE') }}
                      </span>
                      <ul class="ltr:pl-4 rtl:pr-4 mb-0 list-disc">
                        <li
                          v-for="permission in getAgentRolePermissions(agent)"
                          :key="permission"
                          class="text-body-main text-n-slate-11"
                        >
                          {{
                            $t(
                              `CUSTOM_ROLE.PERMISSIONS.${permission.toUpperCase()}`
                            )
                          }}
                        </li>
                      </ul>
                    </div>
                  </div>
                </span>
                <div class="w-px h-3 bg-n-strong rounded-lg" />
                <span
                  v-if="agent.confirmed"
                  class="text-body-main text-n-slate-11"
                >
                  {{ $t('AGENT_MGMT.LIST.VERIFIED') }}
                </span>
                <span
                  v-if="!agent.confirmed"
                  class="text-body-main text-n-slate-11"
                >
                  {{ $t('AGENT_MGMT.LIST.VERIFICATION_PENDING') }}
                </span>
                <span
                  v-if="isSupervisor(agent)"
                  v-tooltip.top="supervisedTeamNames(agent)"
                  class="px-1.5 py-0.5 rounded-md bg-n-teal-3 text-n-teal-11 text-label-small"
                >
                  {{ $t('AGENT_MGMT.LIST.SUPERVISOR') }}
                </span>
              </div>
            </div>
          </div>
          <div class="flex justify-end gap-3">
            <Button
              v-if="showEditAction(agent)"
              v-tooltip.top="$t('AGENT_MGMT.EDIT.BUTTON_TEXT')"
              icon="i-woot-edit-pen"
              slate
              sm
              @click="openEditPopup(agent)"
            />
            <Button
              v-if="showDeleteAction(agent)"
              v-tooltip.top="$t('AGENT_MGMT.DELETE.BUTTON_TEXT')"
              icon="i-woot-bin"
              slate
              sm
              class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
              :is-loading="loading[agent.id]"
              @click="openDeletePopup(agent, index)"
            />
          </div>
        </div>
      </div>
      <AIAgentsSection />
    </template>

    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddAgent @close="hideAddPopup" />
    </woot-modal>

    <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
      <EditAgent
        v-if="showEditPopup"
        :id="currentAgent.id"
        :name="currentAgent.name"
        :provider="currentAgent.provider"
        :type="currentAgent.role"
        :email="currentAgent.email"
        :availability="currentAgent.availability_status"
        :custom-role-id="currentAgent.custom_role_id"
        :supervised-team-ids="currentAgent.supervised_team_ids || []"
        :is-supervisor-view="isSupervisorView"
        @close="hideEditPopup"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('AGENT_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('AGENT_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
    />
  </SettingsLayout>
</template>
