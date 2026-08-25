<script setup>
import { ref, computed, onMounted } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Auth from '../../../../api/auth';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  id: {
    type: Number,
    required: true,
  },
  name: {
    type: String,
    required: true,
  },
  email: {
    type: String,
    default: '',
  },
  type: {
    type: String,
    default: '',
  },
  availability: {
    type: String,
    default: '',
  },
  provider: {
    type: String,
    default: '',
  },
  customRoleId: {
    type: Number,
    default: null,
  },
  // ids dos times que este agente SUPERVISIONA (supervisionar ≠ ser membro)
  supervisedTeamIds: {
    type: Array,
    default: () => [],
  },
  // quem ABRIU o modal é supervisor (não admin): renomear é tudo o que pode.
  // Não confundir com o agente EDITADO ser supervisor — isso é supervisedTeamIds.
  isSupervisorView: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close']);

const { AVAILABILITY_STATUS_KEYS } = wootConstants;

const store = useStore();
const { t } = useI18n();

const agentName = ref(props.name);
const agentAvailability = ref(props.availability);
const agentCredentials = ref({ email: props.email });
// cópia local: só é enviada quando o campo está visível, senão o backend entende
// "chave ausente = não mexa" e a supervisão atual fica preservada.
const supervisedTeamIds = ref([...props.supervisedTeamIds]);

// "Supervisor" é ADMINISTRADOR com times supervisionados: mesmo alcance de um
// admin, menos as telas que o SupervisorSettingsScope bloqueia (Console, Atributos
// Personalizados, Robôs, Macros, Integrações e Fluxo de Conversa). No backend isso
// é `role: administrator` + linhas em team_supervisors — não existe papel próprio.
const SUPERVISOR_ROLE = 'supervisor';
// Quem supervisiona algum time abre o modal como Supervisor, qualquer que seja o
// papel gravado: é o que a pessoa É hoje. Salvar normaliza o papel para
// administrador, que é o que a função significa.
const selectedRoleId = ref(
  props.supervisedTeamIds.length
    ? SUPERVISOR_ROLE
    : props.customRoleId || props.type
);

// No modo supervisor só o Nome está na tela; validar campos escondidos travaria
// o botão salvar por um valor que ele nem pode ver, muito menos corrigir.
const rules = props.isSupervisorView
  ? { agentName: { required, minLength: minLength(1) } }
  : {
      agentName: { required, minLength: minLength(1) },
      selectedRoleId: { required },
      agentAvailability: { required },
    };

const v$ = useVuelidate(rules, {
  agentName,
  selectedRoleId,
  agentAvailability,
});

const pageTitle = computed(
  () => `${t('AGENT_MGMT.EDIT.TITLE')} - ${props.name}`
);

const uiFlags = useMapGetter('agents/getUIFlags');
const getCustomRoles = useMapGetter('customRole/getCustomRoles');
const teams = useMapGetter('teams/getTeams');

onMounted(() => {
  // a lista de agentes não carrega times por conta própria — e no modo
  // supervisor o campo de times nem existe, então não há o que buscar
  if (props.isSupervisorView) return;
  if (!teams.value.length) store.dispatch('teams/get');
});

const roles = computed(() => {
  const defaultRoles = [
    {
      id: 'administrator',
      name: 'administrator',
      label: t('AGENT_MGMT.AGENT_TYPES.ADMINISTRATOR'),
    },
    {
      id: 'agent',
      name: 'agent',
      label: t('AGENT_MGMT.AGENT_TYPES.AGENT'),
    },
    {
      id: SUPERVISOR_ROLE,
      name: SUPERVISOR_ROLE,
      label: t('AGENT_MGMT.AGENT_TYPES.SUPERVISOR'),
    },
  ];

  const customRoles = getCustomRoles.value.map(role => ({
    id: role.id,
    name: `custom_${role.id}`,
    label: role.name,
  }));

  return [...defaultRoles, ...customRoles];
});

const selectedRole = computed(() =>
  roles.value.find(
    role =>
      role.id === selectedRoleId.value || role.name === selectedRoleId.value
  )
);

// O campo pertence à função Supervisor. Trocar para Administrador/Agente é como
// se TIRA a supervisão (o payload manda lista vazia) — era justamente isso que
// faltava antes, quando a chave era omitida para admin e a supervisão ficava
// grudada sem aparecer em lugar nenhum.
// Alterar supervisão é privilégio de admin: no modo supervisor o campo some.
const canSuperviseTeams = computed(
  () => !props.isSupervisorView && selectedRole.value?.name === SUPERVISOR_ROLE
);

// Supervisor sem time nenhum seria um administrador comum, com quem configurou
// achando que deu visibilidade de time. Bloqueia o envio.
const isSupervisorWithoutTeams = computed(
  () => canSuperviseTeams.value && supervisedTeamIds.value.length === 0
);

const statusList = computed(() => {
  return [
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.ONLINE'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.BUSY'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.OFFLINE'),
  ];
});

const availabilityStatuses = computed(() =>
  statusList.value.map((statusLabel, index) => ({
    label: statusLabel,
    value: AVAILABILITY_STATUS_KEYS[index],
    disabled: props.availability === AVAILABILITY_STATUS_KEYS[index],
  }))
);

const editAgent = async () => {
  v$.value.$touch();
  if (v$.value.$invalid || isSupervisorWithoutTeams.value) return;

  try {
    const payload = { id: props.id, name: agentName.value };

    // Supervisor só renomeia: o backend recusa qualquer outra chave vinda dele,
    // então o payload para aqui em vez de descer pelo bloco de função/supervisão.
    if (!props.isSupervisorView) {
      payload.availability = agentAvailability.value;

      const roleName = selectedRole.value.name;
      const isCustomRole = roleName.startsWith('custom_');

      if (isCustomRole) {
        payload.custom_role_id = selectedRole.value.id;
      } else {
        // Supervisor É administrador no backend; a diferenca esta nos times.
        payload.role =
          roleName === SUPERVISOR_ROLE ? 'administrator' : roleName;
        payload.custom_role_id = null;
      }

      // Sempre enviado: o que está na tela é o que fica gravado. Sair da função
      // Supervisor manda lista vazia e é assim que se tira a supervisão.
      payload.supervised_team_ids = canSuperviseTeams.value
        ? supervisedTeamIds.value
        : [];
    }

    await store.dispatch('agents/update', payload);
    useAlert(t('AGENT_MGMT.EDIT.API.SUCCESS_MESSAGE'));
    emit('close');
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};

const resetPassword = async () => {
  try {
    await Auth.resetPassword(agentCredentials.value);
    useAlert(t('AGENT_MGMT.EDIT.PASSWORD_RESET.ADMIN_SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.PASSWORD_RESET.ERROR_MESSAGE'));
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header :header-title="pageTitle" />
    <form class="w-full" @submit.prevent="editAgent">
      <div class="w-full">
        <label :class="{ error: v$.agentName.$error }">
          {{ $t('AGENT_MGMT.EDIT.FORM.NAME.LABEL') }}
          <input
            v-model="agentName"
            type="text"
            :placeholder="$t('AGENT_MGMT.EDIT.FORM.NAME.PLACEHOLDER')"
            @input="v$.agentName.$touch"
          />
        </label>
      </div>

      <!-- Função, times supervisionados e disponibilidade são decisões de admin;
           o supervisor enxerga só o Nome. -->
      <div v-if="!isSupervisorView" class="w-full">
        <label :class="{ error: v$.selectedRoleId.$error }">
          {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.LABEL') }}
          <select v-model="selectedRoleId" @change="v$.selectedRoleId.$touch">
            <option v-for="role in roles" :key="role.id" :value="role.id">
              {{ role.label }}
            </option>
          </select>
          <span v-if="v$.selectedRoleId.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.ERROR') }}
          </span>
        </label>
      </div>

      <!-- Times supervisionados: vem logo abaixo da função porque anda junto com
           ela — supervisionar soma ao papel, não o substitui. -->
      <div v-if="canSuperviseTeams" class="w-full">
        <label class="block">
          {{ $t('AGENT_MGMT.EDIT.FORM.SUPERVISED_TEAMS.LABEL') }}
        </label>
        <p class="mt-0 mb-2 text-n-slate-11 text-label-small">
          {{ $t('AGENT_MGMT.EDIT.FORM.SUPERVISED_TEAMS.DESCRIPTION') }}
        </p>
        <div
          v-if="teams.length"
          class="flex flex-col gap-2.5 p-3 overflow-y-auto border border-solid rounded-lg max-h-44 border-n-weak dark:border-n-strong"
        >
          <div
            v-for="team in teams"
            :key="team.id"
            class="flex items-center gap-2"
          >
            <input
              :id="`supervised-team-${team.id}`"
              v-model="supervisedTeamIds"
              type="checkbox"
              :value="team.id"
              class="m-0"
            />
            <label
              :for="`supervised-team-${team.id}`"
              class="mb-0 text-sm cursor-pointer text-n-slate-12"
            >
              {{ team.name }}
            </label>
          </div>
        </div>
        <p v-else class="mb-4 text-n-slate-11 text-label-small">
          {{ $t('AGENT_MGMT.EDIT.FORM.SUPERVISED_TEAMS.EMPTY') }}
        </p>
        <p
          v-if="teams.length && isSupervisorWithoutTeams"
          class="mt-2 mb-4 text-n-ruby-11 text-label-small"
        >
          {{ $t('AGENT_MGMT.EDIT.FORM.SUPERVISED_TEAMS.REQUIRED') }}
        </p>
        <div v-else class="mb-4" />
      </div>

      <div v-if="!isSupervisorView" class="w-full">
        <label :class="{ error: v$.agentAvailability.$error }">
          {{ $t('PROFILE_SETTINGS.FORM.AVAILABILITY.LABEL') }}
          <select
            v-model="agentAvailability"
            @change="v$.agentAvailability.$touch"
          >
            <option
              v-for="status in availabilityStatuses"
              :key="status.value"
              :value="status.value"
            >
              {{ status.label }}
            </option>
          </select>
          <span v-if="v$.agentAvailability.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_AVAILABILITY.ERROR') }}
          </span>
        </label>
      </div>

      <div class="flex flex-row justify-start w-full gap-2 px-0 py-2">
        <div class="w-[50%] ltr:text-left rtl:text-right">
          <Button
            v-if="!isSupervisorView && provider !== 'saml'"
            ghost
            type="button"
            icon="i-lucide-lock-keyhole"
            class="!px-2"
            :label="$t('AGENT_MGMT.EDIT.PASSWORD_RESET.ADMIN_RESET_BUTTON')"
            @click.prevent="resetPassword"
          />
        </div>
        <div class="w-[50%] flex justify-end items-center gap-2">
          <Button
            faded
            slate
            type="reset"
            :label="$t('AGENT_MGMT.EDIT.CANCEL_BUTTON_TEXT')"
            @click.prevent="emit('close')"
          />
          <Button
            type="submit"
            :label="$t('AGENT_MGMT.EDIT.FORM.SUBMIT')"
            :disabled="
              v$.$invalid || isSupervisorWithoutTeams || uiFlags.isUpdating
            "
            :is-loading="uiFlags.isUpdating"
          />
        </div>
      </div>
    </form>
  </div>
</template>
