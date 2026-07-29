import { createStore } from 'vuex';
import { mount, flushPromises } from '@vue/test-utils';
import TeamsIndex from '../Index.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

// lottie-web cria um canvas no import e o jsdom não implementa — ele entra no
// grafo de módulos de forma transitiva (mesmo truque de ChatList.spec.js).
vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));

const teamMembersGetSpy = vi.fn();

const teams = [
  {
    id: 1,
    name: 'Suporte',
    description: '',
    is_member: true,
    is_supervisor: false,
  },
  {
    id: 2,
    name: 'Vendas',
    description: '',
    is_member: false,
    is_supervisor: true,
  },
];

const members = [
  {
    id: 9,
    name: 'Ana',
    email: 'ana@example.com',
    availability_status: 'online',
  },
];

const SettingsLayoutStub = {
  name: 'SettingsLayout',
  props: ['isLoading', 'loadingMessage', 'noRecordsFound', 'noRecordsMessage'],
  template:
    '<div><slot name="header" /><span class="empty" v-if="noRecordsFound">{{ noRecordsMessage }}</span><slot v-else name="body" /></div>',
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
    '<div class="header"><span class="desc">{{ description }}</span><slot name="actions" /></div>',
};

const ButtonStub = {
  name: 'Button',
  props: ['label', 'icon', 'isLoading'],
  template: '<button :data-icon="icon">{{ label }}</button>',
};

const buildStore = ({ role = 'agent' } = {}) =>
  createStore({
    getters: {
      getCurrentRole: () => role,
    },
    modules: {
      teams: {
        namespaced: true,
        getters: {
          getTeams: () => teams,
          getSupervisedTeams: () => teams.filter(team => team.is_supervisor),
          getUIFlags: () => ({ isFetching: false }),
        },
        actions: { delete: vi.fn() },
      },
      // Espelha o módulo real: os membros só existem no store depois do fetch,
      // que é exatamente o que a expansão precisa disparar.
      teamMembers: {
        namespaced: true,
        state: () => ({ records: {} }),
        getters: {
          getTeamMembers: state => id => state.records[id] || [],
        },
        mutations: {
          set(state, { teamId, data }) {
            state.records = { ...state.records, [teamId]: data };
          },
        },
        actions: {
          get(context, payload) {
            teamMembersGetSpy(payload);
            context.commit('set', { teamId: payload.teamId, data: members });
          },
        },
      },
    },
  });

const mountComponent = (options = {}) =>
  mount(TeamsIndex, {
    global: {
      plugins: [buildStore(options)],
      stubs: {
        SettingsLayout: SettingsLayoutStub,
        BaseSettingsHeader: BaseSettingsHeaderStub,
        Button: ButtonStub,
        Avatar: true,
        Icon: true,
        RouterLink: true,
        'woot-confirm-delete-modal': true,
      },
    },
  });

describe('TeamsIndex supervisor view', () => {
  beforeEach(() => {
    teamMembersGetSpy.mockClear();
  });

  it('lists every team and keeps admin actions for an administrator', () => {
    const wrapper = mountComponent({ role: 'administrator' });
    const text = wrapper.text();
    expect(text).toContain('Suporte');
    expect(text).toContain('Vendas');
    // sem botão de membros: a tela do admin fica exatamente como era
    expect(text).not.toContain('TEAMS_SETTINGS.MEMBERS.SHOW');
    expect(wrapper.findAllComponents(ButtonStub).length).toBeGreaterThan(0);
  });

  it('lists only supervised teams for a supervisor, read-only', () => {
    const wrapper = mountComponent({ role: 'agent' });
    const text = wrapper.text();
    expect(text).toContain('Vendas');
    expect(text).not.toContain('Suporte');
    // nenhum botão de editar/excluir/criar — só o de ver membros
    const buttons = wrapper.findAllComponents(ButtonStub);
    expect(buttons).toHaveLength(1);
    expect(buttons[0].props('icon')).toBe('i-lucide-chevron-down');
  });

  it('fetches and shows the member list on demand', async () => {
    const wrapper = mountComponent({ role: 'agent' });
    await wrapper.findComponent(ButtonStub).trigger('click');
    await flushPromises();

    expect(teamMembersGetSpy).toHaveBeenCalledWith({ teamId: 2 });
    expect(wrapper.text()).toContain('ana@example.com');
  });
});
