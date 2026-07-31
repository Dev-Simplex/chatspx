import { createStore } from 'vuex';
import { mount } from '@vue/test-utils';
import AgentHome from '../Index.vue';
import SettingsLayout from '../../SettingsLayout.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

// lottie-web cria um canvas no import e o jsdom não implementa — ele entra no
// grafo de módulos de forma transitiva (mesmo truque de ChatList.spec.js).
vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));

const agentsGetSpy = vi.fn();
const customRoleGetSpy = vi.fn();
const teamsGetSpy = vi.fn();

// data-icon deixa editar (i-woot-edit-pen) e excluir (i-woot-bin) distinguíveis
const ButtonStub = {
  name: 'Button',
  props: ['label', 'icon', 'isLoading', 'size'],
  template: '<button :data-icon="icon">{{ label }}</button>',
};

const BaseSettingsHeaderStub = {
  name: 'BaseSettingsHeader',
  props: [
    'title',
    'description',
    'linkText',
    'searchPlaceholder',
    'featureName',
  ],
  template:
    '<div><h1>{{ title }}</h1><p>{{ description }}</p><slot name="count" /><slot name="actions" /></div>',
};

const EditAgentStub = {
  name: 'EditAgent',
  props: [
    'id',
    'name',
    'email',
    'type',
    'availability',
    'provider',
    'customRoleId',
    'supervisedTeamIds',
    'isSupervisorView',
  ],
  template: '<div class="edit-agent-stub" />',
};

const teams = [
  { id: 1, name: 'Suporte', is_supervisor: true },
  { id: 2, name: 'Vendas', is_supervisor: false },
];

const agents = [
  {
    id: 11,
    name: 'Ana',
    email: 'ana@example.com',
    role: 'agent',
    confirmed: true,
    availability_status: 'online',
    custom_role_id: null,
    supervised_team_ids: [],
    team_ids: [1],
  },
  {
    id: 12,
    name: 'Bruno',
    email: 'bruno@example.com',
    role: 'agent',
    confirmed: true,
    availability_status: 'offline',
    custom_role_id: null,
    supervised_team_ids: [1],
    team_ids: [1],
  },
];

// Membro só do time 2, que ninguém supervisiona: é ele quem prova que o recorte
// da tela funciona sem a API precisar filtrar nada.
const outsider = {
  id: 13,
  name: 'Carla',
  email: 'carla@example.com',
  role: 'agent',
  confirmed: true,
  availability_status: 'online',
  custom_role_id: null,
  supervised_team_ids: [],
  team_ids: [2],
};

const buildStore = ({
  role = 'administrator',
  agentList = agents,
  teamList = teams,
  isFetchingTeams = false,
} = {}) =>
  createStore({
    getters: {
      // o supervisor logado (id 99) não está na lista que ele administra
      getCurrentUserID: () => 99,
      getCurrentRole: () => role,
    },
    modules: {
      agents: {
        namespaced: true,
        getters: {
          getAgents: () => agentList,
          getUIFlags: () => ({ isFetching: false }),
        },
        actions: { get: agentsGetSpy, delete: vi.fn() },
      },
      customRole: {
        namespaced: true,
        getters: { getCustomRoles: () => [] },
        actions: { getCustomRole: customRoleGetSpy },
      },
      teams: {
        namespaced: true,
        getters: {
          getTeams: () => teamList,
          getSupervisedTeams: () => teamList.filter(team => team.is_supervisor),
          getUIFlags: () => ({ isFetching: isFetchingTeams }),
        },
        actions: { get: teamsGetSpy },
      },
    },
  });

const mountComponent = (storeState = {}) =>
  mount(AgentHome, {
    global: {
      plugins: [buildStore(storeState)],
      stubs: {
        Button: ButtonStub,
        BaseSettingsHeader: BaseSettingsHeaderStub,
        EditAgent: EditAgentStub,
        AIAgentsSection: true,
        Avatar: true,
        WootDeleteModal: true,
        WootLoadingState: true,
        AddAgent: true,
      },
    },
  });

const asSupervisor = (extra = {}) =>
  mountComponent({ role: 'agent', ...extra });

const buttonsWithIcon = (wrapper, icon) =>
  wrapper.findAll(`button[data-icon="${icon}"]`);

describe('Agents Index', () => {
  beforeEach(() => {
    agentsGetSpy.mockClear();
    customRoleGetSpy.mockClear();
    teamsGetSpy.mockClear();
  });

  describe('as an administrator', () => {
    it('keeps the add agent button', () => {
      expect(mountComponent().text()).toContain('Add Agent');
    });

    it('keeps the delete action for other agents', () => {
      expect(buttonsWithIcon(mountComponent(), 'i-woot-bin')).toHaveLength(2);
    });

    it('shows the account-wide description', () => {
      expect(mountComponent().text()).toContain(
        'The list below shows all the agents in your account.'
      );
    });

    it('opens the edit modal outside supervisor mode', async () => {
      const wrapper = mountComponent();
      await buttonsWithIcon(wrapper, 'i-woot-edit-pen')[0].trigger('click');

      expect(
        wrapper.findComponent(EditAgentStub).props('isSupervisorView')
      ).toBe(false);
    });

    // o recorte por time supervisionado é só do supervisor — o admin vê a conta
    it('never scopes the list to the supervised teams', () => {
      const wrapper = mountComponent({ agentList: [...agents, outsider] });

      expect(wrapper.text()).toContain('Carla');
      expect(buttonsWithIcon(wrapper, 'i-woot-edit-pen')).toHaveLength(3);
    });
  });

  // Sem ser admin só se chega aqui pela permissão `team_supervisor`
  describe('as a team supervisor', () => {
    it('hides the add agent button', () => {
      expect(asSupervisor().text()).not.toContain('Add Agent');
    });

    it('hides every delete action', () => {
      expect(buttonsWithIcon(asSupervisor(), 'i-woot-bin')).toHaveLength(0);
    });

    it('keeps the edit action', () => {
      expect(buttonsWithIcon(asSupervisor(), 'i-woot-edit-pen')).toHaveLength(
        2
      );
    });

    it('says the list is scoped to the supervised teams', () => {
      const text = asSupervisor().text();

      expect(text).toContain('Agents in my teams');
      expect(text).toContain(
        'These are the agents of the teams you supervise.'
      );
    });

    it('scopes the empty state to the supervised teams', () => {
      const wrapper = asSupervisor({ agentList: [] });

      expect(wrapper.text()).toContain(
        'There are no agents in the teams you supervise'
      );
    });

    // T4: a API devolve a conta inteira (a store `agents` alimenta menções,
    // participantes e Kanban); quem recorta para "os meus times" é esta tela.
    it('lists only the agents of the supervised teams', () => {
      const wrapper = asSupervisor({ agentList: [...agents, outsider] });

      expect(wrapper.text()).toContain('Ana');
      expect(wrapper.text()).toContain('Bruno');
      expect(wrapper.text()).not.toContain('Carla');
      expect(buttonsWithIcon(wrapper, 'i-woot-edit-pen')).toHaveLength(2);
    });

    // supervisionar um time sem membros esvazia ESTA tela e nada mais
    it('falls back to the empty state when no agent is in the supervised teams', () => {
      const wrapper = asSupervisor({ agentList: [outsider] });

      expect(wrapper.text()).toContain(
        'There are no agents in the teams you supervise'
      );
    });

    it('shows nothing while the supervised teams have not loaded yet', () => {
      const wrapper = asSupervisor({ teamList: [] });

      expect(buttonsWithIcon(wrapper, 'i-woot-edit-pen')).toHaveLength(0);
    });

    // ...e enquanto isso a tela fica CARREGANDO, não no vazio: o recorte depende
    // dos times, então declarar "não há agentes" antes deles chegarem é mentira
    it('waits for the teams before deciding the list is empty', () => {
      const wrapper = asSupervisor({ teamList: [], isFetchingTeams: true });

      expect(wrapper.findComponent(SettingsLayout).props('isLoading')).toBe(
        true
      );
      expect(wrapper.text()).not.toContain(
        'There are no agents in the teams you supervise'
      );
    });

    it('does not wait for the teams when the user is an administrator', () => {
      const wrapper = mountComponent({ isFetchingTeams: true });

      expect(wrapper.findComponent(SettingsLayout).props('isLoading')).toBe(
        false
      );
    });

    it('propagates the supervisor mode to the edit modal', async () => {
      const wrapper = asSupervisor();
      await buttonsWithIcon(wrapper, 'i-woot-edit-pen')[0].trigger('click');

      expect(
        wrapper.findComponent(EditAgentStub).props('isSupervisorView')
      ).toBe(true);
    });
  });
});
