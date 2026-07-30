import { createStore } from 'vuex';
import { mount, flushPromises } from '@vue/test-utils';
import TeamsIndex from '../Index.vue';
import {
  addTeamMembers,
  removeTeamMembers,
} from '../helpers/supervisedTeamMembers';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

// As chamadas de membro batem no axios global (que o jsdom não tem) — o que
// interessa aqui é COM QUE payload elas são chamadas e o refresh que vem depois.
vi.mock('../helpers/supervisedTeamMembers', () => ({
  addTeamMembers: vi.fn(() => Promise.resolve({ data: [] })),
  removeTeamMembers: vi.fn(() => Promise.resolve({})),
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

// Segundo time supervisionado: é dele que sai o pool de quem pode ser
// adicionado ao time 2 (a união dos membros dos times supervisionados).
const twoSupervisedTeams = [
  teams[0],
  teams[1],
  {
    id: 3,
    name: 'Retencao',
    description: '',
    is_member: false,
    is_supervisor: true,
  },
];

const bruno = {
  id: 7,
  name: 'Bruno',
  email: 'bruno@example.com',
  availability_status: 'online',
};

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

// O Dialog real teleporta para o body e usa `showModal()` (ausente no jsdom).
// O stub expõe open/close — que é como a tela abre os diálogos, via template
// ref — e renderiza o conteúdo só quando aberto, igual ao componente de verdade.
const DialogStub = {
  name: 'Dialog',
  props: [
    'type',
    'title',
    'description',
    'confirmButtonLabel',
    'cancelButtonLabel',
    'isLoading',
    'disableConfirmButton',
  ],
  emits: ['confirm', 'close'],
  data() {
    return { isOpen: false };
  },
  methods: {
    open() {
      this.isOpen = true;
    },
    close() {
      this.isOpen = false;
    },
  },
  template: `<div v-if="isOpen" class="dialog">
      <span class="dialog-title">{{ title }}</span>
      <span class="dialog-description">{{ description }}</span>
      <slot />
      <button
        class="dialog-confirm"
        :disabled="disableConfirmButton"
        @click="$emit('confirm')"
      >
        {{ confirmButtonLabel }}
      </button>
    </div>`,
};

const CheckboxStub = {
  name: 'Checkbox',
  props: ['modelValue'],
  emits: ['change'],
  template:
    '<input type="checkbox" :checked="modelValue" @change="$emit(\'change\')" />',
};

const buildStore = ({
  role = 'agent',
  teamsList = teams,
  membersByTeam = { 1: members, 2: members },
} = {}) =>
  createStore({
    getters: {
      getCurrentRole: () => role,
    },
    modules: {
      teams: {
        namespaced: true,
        getters: {
          getTeams: () => teamsList,
          getSupervisedTeams: () =>
            teamsList.filter(team => team.is_supervisor),
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
            context.commit('set', {
              teamId: payload.teamId,
              data: membersByTeam[payload.teamId] || [],
            });
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
        Dialog: DialogStub,
        Checkbox: CheckboxStub,
        Avatar: true,
        Icon: true,
        Spinner: true,
        RouterLink: true,
        'woot-confirm-delete-modal': true,
      },
    },
  });

const findButtonByIcon = (wrapper, icon) =>
  wrapper
    .findAllComponents(ButtonStub)
    .find(button => button.props('icon') === icon);

// Expande a lista de membros do time supervisionado (é o gatilho do fetch).
const expandMembers = async wrapper => {
  await findButtonByIcon(wrapper, 'i-lucide-chevron-down').trigger('click');
  await flushPromises();
};

describe('TeamsIndex supervisor view', () => {
  beforeEach(() => {
    teamMembersGetSpy.mockClear();
    addTeamMembers.mockClear();
    removeTeamMembers.mockClear();
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

  it('lists only supervised teams for a supervisor, without admin actions', () => {
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

  it('removes a member from the team only after confirming', async () => {
    const wrapper = mountComponent({ role: 'agent' });
    await expandMembers(wrapper);

    await findButtonByIcon(wrapper, 'i-lucide-user-minus').trigger('click');
    await flushPromises();

    // um clique só abre a confirmação — nada foi removido ainda
    expect(removeTeamMembers).not.toHaveBeenCalled();
    // texto traduzido: o teste também segura chave crua de i18n
    expect(wrapper.find('.dialog-title').text()).toBe(
      'Remove Ana from the team?'
    );

    await wrapper.find('.dialog-confirm').trigger('click');
    await flushPromises();

    expect(removeTeamMembers).toHaveBeenCalledWith({ teamId: 2, userIds: [9] });
    // a lista é refeita na hora (o DELETE responde sem corpo)
    expect(teamMembersGetSpy).toHaveBeenCalledTimes(2);
    expect(teamMembersGetSpy).toHaveBeenLastCalledWith({ teamId: 2 });
  });

  it('shows a readable message when the backend refuses the change', async () => {
    removeTeamMembers.mockRejectedValueOnce({ response: { status: 401 } });
    const wrapper = mountComponent({ role: 'agent' });
    await expandMembers(wrapper);

    await findButtonByIcon(wrapper, 'i-lucide-user-minus').trigger('click');
    await wrapper.find('.dialog-confirm').trigger('click');
    await flushPromises();

    expect(wrapper.find('.dialog').text()).toContain(
      'You are not allowed to change the members of this team'
    );
  });

  it('adds an agent taken from the other supervised teams', async () => {
    const wrapper = mountComponent({
      role: 'agent',
      teamsList: twoSupervisedTeams,
      membersByTeam: { 2: members, 3: [bruno] },
    });
    await expandMembers(wrapper);

    await findButtonByIcon(wrapper, 'i-lucide-user-plus').trigger('click');
    await flushPromises();

    // o pool é a união dos membros dos times supervisionados menos os deste time
    const dialogText = wrapper.find('.dialog').text();
    expect(dialogText).toContain('bruno@example.com');
    expect(dialogText).not.toContain('ana@example.com');
    expect(dialogText).not.toContain('TEAMS_SETTINGS.');

    await wrapper.find('.dialog input[type="checkbox"]').trigger('change');
    await wrapper.find('.dialog-confirm').trigger('click');
    await flushPromises();

    expect(addTeamMembers).toHaveBeenCalledWith({ teamId: 2, userIds: [7] });
    expect(teamMembersGetSpy).toHaveBeenLastCalledWith({ teamId: 2 });
  });

  it('explains the empty pool when only one team is supervised', async () => {
    const wrapper = mountComponent({ role: 'agent' });
    await expandMembers(wrapper);

    const addButton = findButtonByIcon(wrapper, 'i-lucide-user-plus');
    expect(addButton.exists()).toBe(true);
    expect(addButton.attributes('disabled')).toBeDefined();
    // o motivo fica visível: ele só move agentes entre os times que supervisiona
    expect(wrapper.text()).toContain(
      'You can only move agents between the teams you supervise, so there is nobody to add'
    );
  });
});
