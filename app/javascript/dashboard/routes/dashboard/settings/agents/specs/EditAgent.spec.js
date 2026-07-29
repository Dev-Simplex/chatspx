import { createStore } from 'vuex';
import { mount, flushPromises } from '@vue/test-utils';
import EditAgent from '../EditAgent.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('../../../../../api/auth', () => ({
  default: { resetPassword: vi.fn() },
}));

const updateSpy = vi.fn();
const teamsGetSpy = vi.fn();

const ButtonStub = {
  name: 'Button',
  props: ['label', 'isLoading', 'disabled', 'icon'],
  template: '<button :type="$attrs.type"><slot />{{ label }}</button>',
};

const buildStore = ({ teams = [] } = {}) =>
  createStore({
    modules: {
      agents: {
        namespaced: true,
        getters: { getUIFlags: () => ({ isUpdating: false }) },
        actions: { update: updateSpy },
      },
      customRole: {
        namespaced: true,
        getters: { getCustomRoles: () => [] },
      },
      teams: {
        namespaced: true,
        getters: { getTeams: () => teams },
        actions: { get: teamsGetSpy },
      },
    },
  });

const teams = [
  { id: 1, name: 'Suporte' },
  { id: 2, name: 'Vendas' },
];

const mountComponent = (props = {}, storeState = { teams }) =>
  mount(EditAgent, {
    props: {
      id: 7,
      name: 'Nicolas',
      email: 'nicolas@example.com',
      type: 'agent',
      availability: 'online',
      provider: 'email',
      supervisedTeamIds: [],
      ...props,
    },
    global: {
      plugins: [buildStore(storeState)],
      stubs: { Button: ButtonStub },
    },
  });

const submit = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

const supervisionPayload = () => updateSpy.mock.calls.at(-1)[1];

// O primeiro <select> do formulário é o de Função; o segundo, Disponibilidade.
const roleSelect = wrapper => wrapper.findAll('select')[0];
const selectRole = async (wrapper, value) => {
  await roleSelect(wrapper).setValue(value);
};

describe('EditAgent supervised teams', () => {
  beforeEach(() => {
    updateSpy.mockClear();
    teamsGetSpy.mockClear();
  });

  it('lists every account team with the current supervision pre-checked', () => {
    const wrapper = mountComponent({ supervisedTeamIds: [2] });

    const boxes = wrapper.findAll('input[type="checkbox"]');
    expect(boxes).toHaveLength(2);
    expect(boxes[0].element.checked).toBe(false);
    expect(boxes[1].element.checked).toBe(true);
  });

  it('hides the field for an administrator (já enxerga tudo)', () => {
    const wrapper = mountComponent({ type: 'administrator' });

    expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(0);
  });

  it('shows an empty state when the account has no teams', async () => {
    const wrapper = mountComponent({}, { teams: [] });
    await selectRole(wrapper, 'supervisor');

    expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(0);
    expect(wrapper.text()).toContain('There are no teams in this account yet.');
  });

  it('sends the checked teams on submit, as a plain agent', async () => {
    const wrapper = mountComponent();
    await selectRole(wrapper, 'supervisor');

    await wrapper.findAll('input[type="checkbox"]')[0].setValue(true);
    await submit(wrapper);

    expect(supervisionPayload().supervised_team_ids).toEqual([1]);
    // "Supervisor" é rótulo de tela: no backend continua sendo agente
    expect(supervisionPayload().role).toBe('agent');
  });

  it('clears the supervision when the role goes back to agent', async () => {
    const wrapper = mountComponent({ supervisedTeamIds: [1, 2] });

    await selectRole(wrapper, 'agent');
    await submit(wrapper);

    expect(supervisionPayload().supervised_team_ids).toEqual([]);
  });

  // A supervisão deixou de ser uma seção solta: ela é o desdobramento da função
  it('opens as supervisor when the agent already supervises a team', () => {
    const wrapper = mountComponent({ supervisedTeamIds: [2] });

    expect(roleSelect(wrapper).element.value).toBe('supervisor');
  });

  it('opens as plain agent when there is no supervision', () => {
    const wrapper = mountComponent();

    expect(roleSelect(wrapper).element.value).toBe('agent');
    expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(0);
  });

  it('reveals the teams only after picking supervisor', async () => {
    const wrapper = mountComponent();
    expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(0);

    await selectRole(wrapper, 'supervisor');

    expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(2);
  });

  it('blocks the submit while a supervisor has no team checked', async () => {
    const wrapper = mountComponent();
    await selectRole(wrapper, 'supervisor');

    await submit(wrapper);

    expect(updateSpy).not.toHaveBeenCalled();
  });

  // chave ausente = "não mexa": promover a admin não pode apagar a supervisão em silêncio
  it('omits the key entirely for an administrator', async () => {
    const wrapper = mountComponent({
      type: 'administrator',
      supervisedTeamIds: [1],
    });

    await submit(wrapper);

    expect(supervisionPayload()).not.toHaveProperty('supervised_team_ids');
  });

  it('fetches the teams when the store is empty', () => {
    mountComponent({}, { teams: [] });

    expect(teamsGetSpy).toHaveBeenCalled();
  });
});
