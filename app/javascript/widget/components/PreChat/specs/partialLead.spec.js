/**
 * Bloco 4.18 — o rascunho do lead incompleto, do lado do widget.
 *
 * O que se mede aqui é o que o servidor NÃO pode medir: qual é a etapa em que a pessoa
 * parou, que o formulário calcula, e a disciplina de não mandar uma requisição por tecla
 * nem repetir um rascunho idêntico.
 */
import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import PreChatForm from '../Form.vue';
import { savePartialLead } from 'widget/api/partialLead';

vi.mock('widget/api/partialLead', () => ({ savePartialLead: vi.fn() }));

// `preChatFormEnabled` é obrigatório: `Form.vue#preChatFields` devolve [] sem ele, e o
// formulário não teria campo nenhum para calcular a etapa.
global.chatwootWebChannel = {
  enabledFeatures: [],
  preChatFormEnabled: true,
  preChatFormOptions: { pre_chat_fields: [], pre_chat_message: '' },
};

const CAMPOS = [
  {
    name: 'fullName',
    label: 'Nome',
    type: 'text',
    enabled: true,
    field_type: 'standard',
  },
  {
    name: 'emailAddress',
    label: 'E-mail',
    type: 'email',
    enabled: true,
    field_type: 'standard',
  },
  {
    name: 'phoneNumber',
    label: 'Telefone',
    type: 'text',
    enabled: true,
    field_type: 'standard',
  },
];

const store = createStore({
  modules: {
    conversation: { namespaced: true, getters: { getIsCreating: () => false } },
    appConfig: {
      namespaced: true,
      getters: { getIsUpdatingRoute: () => false },
    },
    campaign: { namespaced: true, getters: { getActiveCampaign: () => ({}) } },
    contacts: { namespaced: true, getters: { getCurrentUser: () => ({}) } },
  },
});

const montar = () =>
  shallowMount(PreChatForm, {
    props: { options: { preChatFields: CAMPOS, preChatMessage: '' } },
    global: {
      plugins: [store],
      mocks: { $t: k => k },
      stubs: { FormKit: true, CustomButton: true, Spinner: true },
    },
  });

describe('4.18 — rascunho do lead incompleto no pré-chat', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    savePartialLead.mockClear();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  const preencher = (wrapper, valores) => {
    wrapper.vm.formValues = { ...wrapper.vm.formValues, ...valores };
    wrapper.vm.schedulePartialLead();
    vi.advanceTimersByTime(1300);
  };

  it('manda o rascunho com a ETAPA EM QUE PAROU — o primeiro campo ainda vazio', () => {
    const wrapper = montar();

    preencher(wrapper, {
      fullName: 'Walisson',
      emailAddress: 'walisson@empresa.com.br',
    });

    expect(savePartialLead).toHaveBeenCalledWith({
      answers: {
        fullName: 'Walisson',
        emailAddress: 'walisson@empresa.com.br',
      },
      step: 3,
      stepKey: 'phoneNumber',
    });
  });

  it('com tudo preenchido, a etapa é a última — chegou ao fim e ainda assim não enviou', () => {
    const wrapper = montar();

    preencher(wrapper, {
      fullName: 'Walisson',
      emailAddress: 'walisson@empresa.com.br',
      phoneNumber: '+5511999998888',
    });

    expect(savePartialLead).toHaveBeenCalledWith(
      expect.objectContaining({ step: 3, stepKey: 'phoneNumber' })
    );
  });

  it('não manda nada enquanto nenhum campo foi preenchido', () => {
    const wrapper = montar();

    preencher(wrapper, {});

    expect(savePartialLead).not.toHaveBeenCalled();
  });

  it('espera o silêncio: digitar três vezes seguidas manda UMA requisição', () => {
    const wrapper = montar();

    wrapper.vm.formValues = { fullName: 'W' };
    wrapper.vm.schedulePartialLead();
    vi.advanceTimersByTime(300);
    wrapper.vm.formValues = { fullName: 'Wal' };
    wrapper.vm.schedulePartialLead();
    vi.advanceTimersByTime(300);
    wrapper.vm.formValues = { fullName: 'Walisson' };
    wrapper.vm.schedulePartialLead();
    vi.advanceTimersByTime(1300);

    expect(savePartialLead).toHaveBeenCalledTimes(1);
    expect(savePartialLead).toHaveBeenCalledWith(
      expect.objectContaining({ answers: { fullName: 'Walisson' } })
    );
  });

  it('não repete um rascunho idêntico ao último enviado', () => {
    const wrapper = montar();

    preencher(wrapper, { fullName: 'Walisson' });
    preencher(wrapper, {});

    expect(savePartialLead).toHaveBeenCalledTimes(1);
  });

  it('o envio do pré-chat cancela o rascunho pendente — quem concluiu não volta a incompleto', () => {
    const wrapper = montar();

    wrapper.vm.formValues = { fullName: 'Walisson', emailAddress: 'w@e.com' };
    wrapper.vm.schedulePartialLead();
    wrapper.vm.onSubmit();
    vi.advanceTimersByTime(3000);

    expect(savePartialLead).not.toHaveBeenCalled();
    expect(wrapper.emitted('submitPreChat')).toHaveLength(1);
  });
});
