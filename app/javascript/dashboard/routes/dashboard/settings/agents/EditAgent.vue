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
// SUPERVISOR é um CARGO à parte de Administrador. Ele supervisiona a conta
// INTEIRA — não se escolhe time, porque nada no recorte dele o impede de ver
// todos. O alcance é o de um administrador, menos as seis telas que o
// SupervisorSettingsScope bloqueia (Console de Super Admin, Atributos
// Personalizados, Robôs, Macros, Integrações e Fluxo de Conversa).
//
// No banco não existe papel `supervisor`: grava-se `role: administrator` mais
// uma linha em team_supervisors para cada time — e é a EXISTÊNCIA dessas linhas
// que dispara a restrição. Por isso o salvar manda todos os times da conta:
// supervisor sem linha nenhuma voltaria a ser administrador comum.
const SUPERVISOR_ROLE = 'supervisor';
// Quem supervisiona algum time abre o modal como Supervisor, qualquer que seja o
// papel gravado: é o que a pessoa É hoje.
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

// Trocar de Supervisor para Administrador/Agente é como se TIRA a supervisão: o
// payload manda lista vazia. Era justamente isso que faltava antes, quando a
// chave era omitida para admin e a supervisão ficava grudada sem aparecer em
// lugar nenhum.
const isSupervisorRole = computed(
  () => !props.isSupervisorView && selectedRole.value?.name === SUPERVISOR_ROLE
);

// Conta sem nenhum time não consegue registrar supervisão — as linhas de
// team_supervisors são por time. Sem esta guarda o salvar passaria e criaria um
// administrador comum, com as seis telas de volta, sem ninguém perceber.
const supervisorWithoutTeamsInAccount = computed(
  () => isSupervisorRole.value && teams.value.length === 0
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
  if (v$.value.$invalid || supervisorWithoutTeamsInAccount.value) return;

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
      // Supervisor abrange a conta inteira; qualquer outro cargo zera a supervisão.
      payload.supervised_team_ids = isSupervisorRole.value
        ? teams.value.map(team => team.id)
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

      <!-- Supervisor abrange a conta inteira: não há time a escolher. Só resta
           avisar quando a conta ainda não tem time nenhum, caso em que não há
           como registrar a supervisão. -->
      <div v-if="supervisorWithoutTeamsInAccount" class="w-full">
        <p class="mb-4 text-n-ruby-11 text-label-small">
          {{ $t('AGENT_MGMT.EDIT.FORM.SUPERVISED_TEAMS.EMPTY') }}
        </p>
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
              v$.$invalid ||
              supervisorWithoutTeamsInAccount ||
              uiFlags.isUpdating
            "
            :is-loading="uiFlags.isUpdating"
          />
        </div>
      </div>
    </form>
  </div>
</template>
