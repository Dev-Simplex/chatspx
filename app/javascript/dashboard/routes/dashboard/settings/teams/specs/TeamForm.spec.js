import { mount, flushPromises } from '@vue/test-utils';
import TeamForm from '../TeamForm.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const showSpy = vi.fn();
const updateSpy = vi.fn();
vi.mock('dashboard/api/teamDistribuicao', () => ({
  default: {
    show: (...args) => showSpy(...args),
    update: (...args) => updateSpy(...args),
  },
}));

const respostaVazia = {
  data: {
    configurado: false,
    politica: { ativo: false },
    pool: [],
    candidatos: [],
    time: { nome: 'Vendas' },
    horario_definido: true,
  },
};

const montar = (props = {}) =>
  mount(TeamForm, {
    props: { onSubmit: vi.fn(), submitButtonText: 'Salvar', ...props },
    global: {
      mocks: { $t: chave => chave },
      stubs: { FormInput: true, NextButton: true, Spinner: true },
    },
  });

describe('TeamForm', () => {
  beforeEach(() => {
    showSpy.mockReset().mockResolvedValue(respostaVazia);
    updateSpy.mockReset().mockResolvedValue(respostaVazia);
  });

  // O pool só pode ser montado com quem JÁ é membro: o motor descarta não-membro em silêncio,
  // e foi assim que o time de vendas da Tozi ficou com o pool inteiro inválido sem ninguém
  // perceber. No cadastro o time ainda não tem membros, então oferecer a lista ali produziria
  // fila vazia ou inválida.
  describe('cadastro (sem teamId)', () => {
    it('nao carrega a configuracao de rodizio', () => {
      montar();

      expect(showSpy).not.toHaveBeenCalled();
    });

    it('avisa que a fila se monta depois de adicionar os membros', () => {
      const wrapper = montar();

      expect(wrapper.text()).toContain(
        'TEAMS_SETTINGS.FORM.AUTO_ASSIGN.RODIZIO_DEPOIS'
      );
    });

    it('continua oferecendo o checkbox de atribuicao automatica', () => {
      const wrapper = montar();

      expect(wrapper.find('input[type="checkbox"]').exists()).toBe(true);
    });
  });

  describe('edicao (com teamId)', () => {
    it('carrega a configuracao daquele time', async () => {
      montar({ teamId: 7 });
      await flushPromises();

      expect(showSpy).toHaveBeenCalledWith(7);
    });

    it('nao mostra o aviso de "monta depois"', async () => {
      const wrapper = montar({ teamId: 7 });
      await flushPromises();

      expect(wrapper.text()).not.toContain(
        'TEAMS_SETTINGS.FORM.AUTO_ASSIGN.RODIZIO_DEPOIS'
      );
    });

    // Um botão só: dois "salvar" na mesma tela é pergunta sem resposta boa.
    it('salva o rodizio junto com o time, num submit so', async () => {
      const onSubmit = vi.fn();
      const wrapper = montar({ teamId: 7, onSubmit });
      await flushPromises();

      wrapper.vm.state.title = 'Vendas';
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(updateSpy).toHaveBeenCalled();
      expect(onSubmit).toHaveBeenCalled();
    });
  });

  // São motores DIFERENTES: o de cima é a atribuição automática nativa do Chatwoot (qualquer
  // membro com capacidade), o de baixo é o Motor de Distribuição do fork (rodízio em ordem).
  // Ligar os dois faz um desfazer a escolha do outro.
  describe('aviso dos dois motores', () => {
    it('nao aparece com o rodizio desligado', async () => {
      const wrapper = montar({ teamId: 7 });
      await flushPromises();

      expect(wrapper.text()).not.toContain(
        'TEAMS_SETTINGS.FORM.AUTO_ASSIGN.CONFLITO_RODIZIO'
      );
    });

    it('aparece quando os DOIS estao ligados', async () => {
      showSpy.mockResolvedValue({
        data: { ...respostaVazia.data, politica: { ativo: true } },
      });
      const wrapper = montar({ teamId: 7 });
      await flushPromises();

      expect(wrapper.text()).toContain(
        'TEAMS_SETTINGS.FORM.AUTO_ASSIGN.CONFLITO_RODIZIO'
      );
    });

    it('nao aparece quando so o rodizio esta ligado', async () => {
      showSpy.mockResolvedValue({
        data: { ...respostaVazia.data, politica: { ativo: true } },
      });
      const wrapper = montar({
        teamId: 7,
        formData: { allow_auto_assign: false },
      });
      await flushPromises();

      expect(wrapper.text()).not.toContain(
        'TEAMS_SETTINGS.FORM.AUTO_ASSIGN.CONFLITO_RODIZIO'
      );
    });
  });
});
