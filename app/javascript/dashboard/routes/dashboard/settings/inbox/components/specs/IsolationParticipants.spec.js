import { createStore } from 'vuex';
import { mount } from '@vue/test-utils';
import IsolationParticipants from '../IsolationParticipants.vue';

const AvatarStub = {
  name: 'Avatar',
  props: {
    src: { type: String, default: '' },
    name: { type: String, default: '' },
    size: { type: Number, default: 32 },
  },
  template: '<span data-testid="avatar" />',
};

const teams = [
  { id: 9, name: 'Vendas' },
  { id: 10, name: 'Suporte' },
];

const buildStore = () =>
  createStore({
    modules: {
      teams: {
        namespaced: true,
        getters: { getTeams: () => teams },
      },
    },
  });

// 5 agentes comuns + 1 supervisor + 1 administrador (o mesmo elenco do mockup):
// o admin nunca entra na tabela e o supervisor entra sem caixa de selecao.
const agents = [
  { id: 1, name: 'Cibele', email: 'cibele@x.com', role: 'agent' },
  { id: 2, name: 'Gabriel', email: 'gabriel@x.com', role: 'agent' },
  { id: 3, name: 'Marina', email: 'marina@x.com', role: 'agent' },
  { id: 4, name: 'Juliana', email: 'juliana@x.com', role: 'agent' },
  { id: 7, name: 'Rafael', email: 'rafael@x.com', role: 'agent' },
  {
    id: 5,
    name: 'Walisson',
    email: 'walisson@x.com',
    role: 'agent',
    supervised_team_ids: [9],
  },
  { id: 6, name: 'Ana', email: 'ana@x.com', role: 'administrator' },
];

const mountComponent = (
  modelValue = [1, 2, 3, 4, 7, 5],
  isolationType = 'agent_message'
) =>
  mount(IsolationParticipants, {
    props: { agents, modelValue, isolationType },
    global: {
      plugins: [buildStore()],
      stubs: { Avatar: AvatarStub },
    },
  });

describe('IsolationParticipants', () => {
  it('deixa o administrador fora da lista e explica o porque', () => {
    const wrapper = mountComponent();

    expect(wrapper.text()).not.toContain('Ana');
    expect(wrapper.text()).toContain(
      'Administradores não aparecem aqui: eles nunca são isolados por agente.'
    );
  });

  it('conta os marcados sobre o total listado, supervisor incluso', () => {
    // 4 selecionaveis marcados, 1 desmarcado, 1 supervisor isento => "4 de 6 marcados"
    const wrapper = mountComponent([1, 2, 4, 7, 5]);

    expect(wrapper.text()).toContain('4 de 6 marcados');
  });

  it('mostra o supervisor sem caixa de selecao, com o time e o selo de isento', () => {
    const wrapper = mountComponent();
    const rows = wrapper.findAll('tbody tr');
    const supervisorRow = rows[rows.length - 1];

    expect(supervisorRow.text()).toContain('Walisson');
    expect(supervisorRow.text()).toContain('supervisor do time Vendas');
    // a isencao dele e por TIME, nao pela caixa inteira — o selo diz isso
    expect(supervisorRow.text()).toContain('isento no time dele');
    expect(supervisorRow.find('input[type="checkbox"]').exists()).toBe(false);
  });

  it('marca a linha desmarcada com o selo "vê tudo"', () => {
    const wrapper = mountComponent([1, 2, 4, 7, 5]);
    const marinaRow = wrapper
      .findAll('tbody tr')
      .find(row => row.text().includes('Marina'));

    expect(marinaRow.text()).toContain('vê tudo');
  });

  it('desmarcar tira so aquele agente e mantem o supervisor participando', async () => {
    const wrapper = mountComponent();
    const marinaRow = wrapper
      .findAll('tbody tr')
      .find(row => row.text().includes('Marina'));

    await marinaRow.find('input[type="checkbox"]').setValue(false);

    const [emitted] = wrapper.emitted('update:modelValue').at(-1);
    expect(emitted).toEqual([1, 2, 4, 7, 5]);
  });

  it('selecionar todos devolve os selecionaveis mais o supervisor', async () => {
    const wrapper = mountComponent([1]);

    await wrapper.find('thead input[type="checkbox"]').setValue(true);

    const [emitted] = wrapper.emitted('update:modelValue').at(-1);
    expect(emitted).toEqual([1, 2, 3, 4, 7, 5]);
  });

  it('desmarcar todos ainda sobe o supervisor, que nunca vira excecao', async () => {
    const wrapper = mountComponent([1, 2, 3, 4, 7, 5]);

    await wrapper.find('thead input[type="checkbox"]').setValue(false);

    const [emitted] = wrapper.emitted('update:modelValue').at(-1);
    expect(emitted).toEqual([5]);
  });

  it('mostra todo mundo marcado quando a caixa nao trouxe a lista', async () => {
    // Payload antigo em cache: `null` nao pode virar "isenta todo mundo".
    const wrapper = mountComponent(null);

    expect(wrapper.text()).toContain('5 de 6 marcados');
    expect(wrapper.text()).not.toContain('vê tudo');

    const marinaRow = wrapper
      .findAll('tbody tr')
      .find(row => row.text().includes('Marina'));
    await marinaRow.find('input[type="checkbox"]').setValue(false);

    const [emitted] = wrapper.emitted('update:modelValue').at(-1);
    expect(emitted).toEqual([1, 2, 4, 7, 5]);
  });

  it('deixa o "selecionar todos" indeterminado quando ha excecao', () => {
    const wrapper = mountComponent([1, 2, 4, 7, 5]);
    const selectAll = wrapper.find('thead input[type="checkbox"]');

    expect(selectAll.element.indeterminate).toBe(true);
    expect(selectAll.element.checked).toBe(false);
  });

  // No isolamento por TIME ninguem e isento por natureza: nem administrador, nem
  // supervisor. O texto tem de dizer isso, senao a tela promete uma isencao que o
  // backend nao da (ver TeamMessageIsolation).
  describe('no card de isolamento por time', () => {
    const mountTeamCard = (modelValue = [1, 2, 3, 4, 7, 5]) =>
      mountComponent(modelValue, 'team_message');

    it('nao promete que o administrador escapa da regra', () => {
      const wrapper = mountTeamCard();

      expect(wrapper.text()).not.toContain('Ana');
      expect(wrapper.text()).toContain(
        'Administradores não aparecem aqui — mas eles também não escapam desta regra.'
      );
      expect(wrapper.text()).not.toContain('eles nunca são isolados');
    });

    it('nao chama o supervisor de isento, porque aqui ele nao e', () => {
      const wrapper = mountTeamCard();
      const rows = wrapper.findAll('tbody tr');
      const supervisorRow = rows[rows.length - 1];

      expect(supervisorRow.text()).toContain('participa sempre');
      expect(supervisorRow.text()).not.toContain('isento');
      expect(supervisorRow.find('input[type="checkbox"]').exists()).toBe(false);
      expect(wrapper.text()).toContain(
        'A supervisão de time isenta do isolamento por agente, não deste'
      );
    });

    it('conta o supervisor entre os isolados, porque ele segue isolado', () => {
      // mesmos 4 selecionaveis marcados do card de agente, mas aqui o supervisor
      // tambem segue isolado => "5 de 6" em vez de "4 de 6"
      const wrapper = mountTeamCard([1, 2, 4, 7, 5]);

      expect(wrapper.text()).toContain('5 de 6 marcados');
    });

    it('salva a mesma lista de participantes que o card de agente', async () => {
      // o selo e o texto mudam; o que vai para o servidor, nao
      const wrapper = mountTeamCard();
      const marinaRow = wrapper
        .findAll('tbody tr')
        .find(row => row.text().includes('Marina'));

      await marinaRow.find('input[type="checkbox"]').setValue(false);

      const [emitted] = wrapper.emitted('update:modelValue').at(-1);
      expect(emitted).toEqual([1, 2, 4, 7, 5]);
    });
  });
});
