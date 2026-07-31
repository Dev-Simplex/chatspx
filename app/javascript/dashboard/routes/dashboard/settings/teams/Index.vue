<script setup>
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import { computed, ref } from 'vue';
import { picoSearch } from '@scmmishra/pico-search';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import {
  addTeamMembers,
  removeTeamMembers,
} from './helpers/supervisedTeamMembers';

const store = useStore();
const { t } = useI18n();
const getters = useStoreGetters();
const { isAdmin } = useAdmin();

const loading = ref({});
const searchQuery = ref('');

const allTeams = useMapGetter('teams/getTeams');
const supervisedTeams = useMapGetter('teams/getSupervisedTeams');

// Quem chega aqui sem ser admin só pode ter entrado pela permissão
// `team_supervisor` (ver teams.routes.js), então a tela mostra apenas os times
// supervisionados e as únicas ações liberadas são sobre os MEMBROS (adicionar e
// remover). Criar, editar e excluir time continuam exclusivos do admin.
const isSupervisorView = computed(() => !isAdmin.value);

const teamsList = computed(() =>
  isSupervisorView.value ? supervisedTeams.value : allTeams.value
);

const filteredTeamsList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return teamsList.value;
  return picoSearch(teamsList.value, query, ['name', 'description']);
});

// Lista de membros do supervisor: um time expandido por vez, buscada sob
// demanda — o endpoint /team_members já é liberado a agentes.
const expandedTeamId = ref(null);
const membersLoading = ref({});
const loadedMemberTeamIds = ref(new Set());
const getTeamMembersFn = useMapGetter('teamMembers/getTeamMembers');

const membersOf = teamId => getTeamMembersFn.value(teamId) || [];

// `loadedMemberTeamIds` (e não `membersOf(id).length`) é o que diz se já
// buscamos: um time legitimamente sem membros seria refetchado para sempre.
const fetchMembers = async (teamId, { force = false } = {}) => {
  if (!force && loadedMemberTeamIds.value.has(teamId)) return;
  try {
    membersLoading.value[teamId] = true;
    await store.dispatch('teamMembers/get', { teamId });
    loadedMemberTeamIds.value = new Set(loadedMemberTeamIds.value).add(teamId);
  } finally {
    membersLoading.value[teamId] = false;
  }
};

const toggleMembers = async team => {
  if (expandedTeamId.value === team.id) {
    expandedTeamId.value = null;
    return;
  }
  expandedTeamId.value = team.id;
  try {
    await fetchMembers(team.id);
  } catch (error) {
    useAlert(t('TEAMS_SETTINGS.MEMBERS.API_ERROR'));
  }
};

// O backend barra quando o time não é supervisionado ou quando algum id está
// fora do pool permitido. Na prática isso chega como 401 (o
// `RequestExceptionHandler` traduz `Pundit::NotAuthorizedError` em
// `render_unauthorized`), e 403 fica coberto por garantia. Sem esta tradução o
// usuário leria "Request failed with status code 401" — ou nada.
const memberActionError = error => {
  if ([401, 403].includes(error?.response?.status)) {
    return t('TEAMS_SETTINGS.MEMBERS.FORBIDDEN');
  }
  return t('TEAMS_SETTINGS.MEMBERS.ACTION_ERROR');
};

// --- remover membro (sempre com confirmação) ---------------------------------
const removeDialogRef = ref(null);
const removalTarget = ref(null);
const isRemovingMember = ref(false);
const removeError = ref('');

const openRemoveMember = (team, member) => {
  removalTarget.value = { team, member };
  removeError.value = '';
  removeDialogRef.value?.open();
};

const closeRemoveMember = () => {
  removalTarget.value = null;
  removeError.value = '';
};

const confirmRemoveMember = async () => {
  if (!removalTarget.value) return;
  const { team, member } = removalTarget.value;
  try {
    isRemovingMember.value = true;
    removeError.value = '';
    await removeTeamMembers({ teamId: team.id, userIds: [member.id] });
    // O DELETE responde `head :ok` (sem corpo), então a lista só reflete depois
    // de um GET novo — é o que mantém a tela em dia na hora.
    await fetchMembers(team.id, { force: true });
    useAlert(t('TEAMS_SETTINGS.MEMBERS.REMOVE.SUCCESS', { name: member.name }));
    removeDialogRef.value?.close();
    removalTarget.value = null;
  } catch (error) {
    removeError.value = memberActionError(error);
  } finally {
    isRemovingMember.value = false;
  }
};

const removeDialogTitle = computed(() =>
  t('TEAMS_SETTINGS.MEMBERS.REMOVE.TITLE', {
    name: removalTarget.value?.member?.name ?? '',
  })
);

const removeDialogMessage = computed(() =>
  t('TEAMS_SETTINGS.MEMBERS.REMOVE.MESSAGE', {
    name: removalTarget.value?.member?.name ?? '',
    teamName: removalTarget.value?.team?.name ?? '',
  })
);

// --- adicionar membro -------------------------------------------------------
const addDialogRef = ref(null);
const addTarget = ref(null);
const isPoolLoading = ref(false);
const isAddingMembers = ref(false);
const addError = ref('');
const selectedPoolIds = ref([]);

// DECISÃO DE PRODUTO: o pool de quem o supervisor pode adicionar é a UNIÃO dos
// membros de TODOS os times que ele supervisiona, menos quem já está neste time.
// Ele MOVE gente entre os times dele, não traz gente de fora. Consequência
// esperada (não é bug): quem supervisiona um único time tem pool vazio.
const poolFor = teamId => {
  const currentIds = new Set(membersOf(teamId).map(({ id }) => id));
  const pool = new Map();
  supervisedTeams.value.forEach(team => {
    if (team.id === teamId) return;
    membersOf(team.id).forEach(member => {
      if (currentIds.has(member.id)) return;
      pool.set(member.id, member);
    });
  });
  return [...pool.values()];
};

const addPool = computed(() =>
  addTarget.value ? poolFor(addTarget.value.id) : []
);

// Um único time supervisionado ⇒ não existe de onde tirar ninguém. Isso se
// afirma sem nenhuma requisição, então o botão já nasce desabilitado com a
// explicação ao lado — ninguém precisa abrir um diálogo vazio para descobrir.
const hasSourceTeams = computed(() => supervisedTeams.value.length > 1);

const openAddMembers = async team => {
  addTarget.value = team;
  selectedPoolIds.value = [];
  addError.value = '';
  addDialogRef.value?.open();
  try {
    isPoolLoading.value = true;
    // O pool depende dos membros de TODOS os times supervisionados, e a lista é
    // carregada sob demanda — busca o que ainda falta (os já carregados são
    // no-op em `fetchMembers`).
    await Promise.all(supervisedTeams.value.map(({ id }) => fetchMembers(id)));
  } catch (error) {
    addError.value = memberActionError(error);
  } finally {
    isPoolLoading.value = false;
  }
};

const closeAddMembers = () => {
  addTarget.value = null;
  selectedPoolIds.value = [];
  addError.value = '';
};

const isPoolMemberSelected = memberId =>
  selectedPoolIds.value.includes(memberId);

const togglePoolMember = memberId => {
  selectedPoolIds.value = isPoolMemberSelected(memberId)
    ? selectedPoolIds.value.filter(id => id !== memberId)
    : [...selectedPoolIds.value, memberId];
};

const confirmAddMembers = async () => {
  if (!addTarget.value || !selectedPoolIds.value.length) return;
  const team = addTarget.value;
  const userIds = [...selectedPoolIds.value];
  try {
    isAddingMembers.value = true;
    addError.value = '';
    await addTeamMembers({ teamId: team.id, userIds });
    // O POST responde só com os recém-adicionados; o GET devolve a lista
    // completa do time, que é o que a tela mostra.
    await fetchMembers(team.id, { force: true });
    useAlert(t('TEAMS_SETTINGS.MEMBERS.ADD.SUCCESS', { n: userIds.length }));
    addDialogRef.value?.close();
    addTarget.value = null;
    selectedPoolIds.value = [];
  } catch (error) {
    addError.value = memberActionError(error);
  } finally {
    isAddingMembers.value = false;
  }
};

const addDialogTitle = computed(() =>
  t('TEAMS_SETTINGS.MEMBERS.ADD.TITLE', {
    teamName: addTarget.value?.name ?? '',
  })
);

const uiFlags = computed(() => getters['teams/getUIFlags'].value);

const deleteTeam = async ({ id }) => {
  try {
    loading.value[id] = true;
    await store.dispatch('teams/delete', id);
    useAlert(t('TEAMS_SETTINGS.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('TEAMS_SETTINGS.DELETE.API.ERROR_MESSAGE'));
  } finally {
    loading.value[id] = false;
  }
};

const showDeletePopup = ref(false);
const selectedTeam = ref({});

const openDelete = team => {
  showDeletePopup.value = true;
  selectedTeam.value = team;
};

const closeDelete = () => {
  showDeletePopup.value = false;
  selectedTeam.value = {};
};

const confirmDeletion = () => {
  deleteTeam(selectedTeam.value);
  closeDelete();
};

const deleteConfirmText = computed(
  () => `${t('TEAMS_SETTINGS.DELETE.CONFIRM.YES')} ${selectedTeam.value.name}`
);

const deleteRejectText = computed(() => t('TEAMS_SETTINGS.DELETE.CONFIRM.NO'));

const confirmDeleteTitle = computed(() =>
  t('TEAMS_SETTINGS.DELETE.CONFIRM.TITLE', {
    teamName: selectedTeam.value.name,
  })
);

const confirmPlaceHolderText = computed(() =>
  t('TEAMS_SETTINGS.DELETE.CONFIRM.PLACE_HOLDER', {
    teamName: selectedTeam.value.name,
  })
);
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('TEAMS_SETTINGS.LOADING')"
    :no-records-found="!teamsList.length"
    :no-records-message="
      isSupervisorView
        ? $t('TEAMS_SETTINGS.LIST.404_SUPERVISOR')
        : $t('TEAMS_SETTINGS.LIST.404')
    "
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('TEAMS_SETTINGS.HEADER')"
        :description="
          isSupervisorView
            ? $t('TEAMS_SETTINGS.DESCRIPTION_SUPERVISOR')
            : $t('TEAMS_SETTINGS.DESCRIPTION')
        "
        :link-text="$t('TEAMS_SETTINGS.LEARN_MORE')"
        :search-placeholder="$t('TEAMS_SETTINGS.SEARCH_PLACEHOLDER')"
        feature-name="team_management"
      >
        <template v-if="teamsList?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('TEAMS_SETTINGS.COUNT', { n: teamsList.length }) }}
          </span>
        </template>
        <template #actions>
          <router-link v-if="isAdmin" :to="{ name: 'settings_teams_new' }">
            <Button :label="$t('TEAMS_SETTINGS.NEW_TEAM')" size="sm" />
          </router-link>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <span
        v-if="!filteredTeamsList.length && searchQuery"
        class="flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
      >
        {{ $t('TEAMS_SETTINGS.NO_RESULTS') }}
      </span>

      <div
        v-else
        class="divide-y divide-n-weak border border-n-weak rounded-xl"
      >
        <div v-for="team in filteredTeamsList" :key="team.id" class="px-4 py-4">
          <div class="flex justify-between flex-row items-start gap-4">
            <div class="flex items-start gap-4">
              <div
                class="flex items-center flex-shrink-0 size-10 justify-center rounded-xl outline outline-1 outline-n-weak -outline-offset-1"
              >
                <Icon
                  icon="i-lucide-users-round"
                  class="size-4 text-n-slate-11"
                />
              </div>
              <div class="flex flex-col items-start gap-1">
                <span class="block text-heading-3 text-n-slate-12 capitalize">
                  {{ team.name }}
                </span>
                <p class="mb-0 text-n-slate-11 text-body-main">
                  {{ team.description }}
                </p>
              </div>
            </div>
            <div class="flex justify-end gap-3">
              <Button
                v-if="isSupervisorView"
                :label="
                  expandedTeamId === team.id
                    ? $t('TEAMS_SETTINGS.MEMBERS.HIDE')
                    : $t('TEAMS_SETTINGS.MEMBERS.SHOW')
                "
                :icon="
                  expandedTeamId === team.id
                    ? 'i-lucide-chevron-up'
                    : 'i-lucide-chevron-down'
                "
                slate
                sm
                :is-loading="membersLoading[team.id]"
                @click="toggleMembers(team)"
              />
              <router-link
                v-if="isAdmin"
                :to="{
                  name: 'settings_teams_edit',
                  params: { teamId: team.id },
                }"
              >
                <Button
                  v-tooltip.top="$t('TEAMS_SETTINGS.LIST.EDIT_TEAM')"
                  icon="i-woot-settings"
                  slate
                  sm
                />
              </router-link>

              <Button
                v-if="isAdmin"
                v-tooltip.top="$t('TEAMS_SETTINGS.DELETE.BUTTON_TEXT')"
                icon="i-woot-bin"
                slate
                sm
                class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                :is-loading="loading[team.id]"
                @click="openDelete(team)"
              />
            </div>
          </div>

          <div
            v-if="
              isSupervisorView &&
              expandedTeamId === team.id &&
              !membersLoading[team.id]
            "
            class="mt-4 ml-14 flex flex-col gap-3"
          >
            <span
              v-if="!membersOf(team.id).length"
              class="text-body-main text-n-slate-11"
            >
              {{ $t('TEAMS_SETTINGS.MEMBERS.EMPTY') }}
            </span>
            <template v-else>
              <span class="text-body-main text-n-slate-11">
                {{
                  $t('TEAMS_SETTINGS.MEMBERS.COUNT', {
                    n: membersOf(team.id).length,
                  })
                }}
              </span>
              <div
                v-for="member in membersOf(team.id)"
                :key="member.id"
                class="flex items-center gap-3"
              >
                <Avatar
                  :src="member.thumbnail"
                  :name="member.name"
                  :status="member.availability_status"
                  :size="28"
                />
                <span class="text-body-main text-n-slate-12 capitalize">
                  {{ member.name }}
                </span>
                <span class="text-body-main text-n-slate-11">
                  {{ member.email }}
                </span>
                <Button
                  v-tooltip.top="$t('TEAMS_SETTINGS.MEMBERS.REMOVE.BUTTON')"
                  :aria-label="$t('TEAMS_SETTINGS.MEMBERS.REMOVE.BUTTON')"
                  icon="i-lucide-user-minus"
                  ghost
                  slate
                  xs
                  class="ml-auto hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                  @click="openRemoveMember(team, member)"
                />
              </div>
            </template>

            <div class="flex flex-wrap items-center gap-3 pt-1">
              <Button
                :label="$t('TEAMS_SETTINGS.MEMBERS.ADD.BUTTON')"
                icon="i-lucide-user-plus"
                slate
                sm
                :disabled="!hasSourceTeams"
                @click="openAddMembers(team)"
              />
              <span
                v-if="!hasSourceTeams"
                class="text-body-main text-n-slate-11 max-w-lg"
              >
                {{ $t('TEAMS_SETTINGS.MEMBERS.ADD.SINGLE_TEAM') }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <Dialog
        ref="removeDialogRef"
        type="alert"
        :title="removeDialogTitle"
        :description="removeDialogMessage"
        :confirm-button-label="$t('TEAMS_SETTINGS.MEMBERS.REMOVE.CONFIRM')"
        :cancel-button-label="$t('TEAMS_SETTINGS.MEMBERS.REMOVE.CANCEL')"
        :is-loading="isRemovingMember"
        @confirm="confirmRemoveMember"
        @close="closeRemoveMember"
      >
        <p v-if="removeError" class="mb-0 text-body-main text-n-ruby-11">
          {{ removeError }}
        </p>
      </Dialog>

      <Dialog
        ref="addDialogRef"
        :title="addDialogTitle"
        :description="$t('TEAMS_SETTINGS.MEMBERS.ADD.DESC')"
        :confirm-button-label="$t('TEAMS_SETTINGS.MEMBERS.ADD.CONFIRM')"
        :cancel-button-label="$t('TEAMS_SETTINGS.MEMBERS.ADD.CANCEL')"
        :is-loading="isAddingMembers"
        :disable-confirm-button="!selectedPoolIds.length"
        @confirm="confirmAddMembers"
        @close="closeAddMembers"
      >
        <div class="flex flex-col gap-3">
          <div
            v-if="isPoolLoading"
            class="flex items-center gap-2 text-body-main text-n-slate-11"
          >
            <Spinner :size="16" class="text-n-blue-11" />
            {{ $t('TEAMS_SETTINGS.MEMBERS.ADD.LOADING') }}
          </div>
          <p
            v-else-if="!addPool.length"
            class="mb-0 text-body-main text-n-slate-11"
          >
            {{ $t('TEAMS_SETTINGS.MEMBERS.ADD.EMPTY_POOL') }}
          </p>
          <div v-else class="flex flex-col gap-1 max-h-72 overflow-y-auto">
            <label
              v-for="member in addPool"
              :key="member.id"
              class="flex items-center gap-3 py-2 px-1 rounded-lg cursor-pointer hover:bg-n-alpha-1"
            >
              <Checkbox
                :model-value="isPoolMemberSelected(member.id)"
                @change="togglePoolMember(member.id)"
              />
              <Avatar
                :src="member.thumbnail"
                :name="member.name"
                :status="member.availability_status"
                :size="28"
              />
              <span class="text-body-main text-n-slate-12 capitalize">
                {{ member.name }}
              </span>
              <span class="text-body-main text-n-slate-11 truncate">
                {{ member.email }}
              </span>
            </label>
          </div>
          <p v-if="addError" class="mb-0 text-body-main text-n-ruby-11">
            {{ addError }}
          </p>
        </div>
      </Dialog>
    </template>
    <woot-confirm-delete-modal
      v-if="showDeletePopup"
      v-model:show="showDeletePopup"
      :title="confirmDeleteTitle"
      :message="$t('TEAMS_SETTINGS.DELETE.CONFIRM.MESSAGE')"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
      :confirm-value="selectedTeam.name"
      :confirm-place-holder-text="confirmPlaceHolderText"
      @on-confirm="confirmDeletion"
      @on-close="closeDelete"
    />
  </SettingsLayout>
</template>
