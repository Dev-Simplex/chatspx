/**
 * BLOCO 3.15 — a CASCA, montada de verdade.
 *
 * O spec do helper (`widget/helpers/specs/preChatFieldRules.spec.js`) prova a
 * regra isolada. Este prova a JUNÇÃO — que é onde esta execução já se machucou:
 * o pior defeito da onda foi produtor e consumidor certos sozinhos e errados
 * juntos. Aqui o componente é montado e perguntado o que ele renderiza e o que
 * ele emite.
 */
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Form from '../Form.vue';

const store = () =>
  createStore({
    modules: {
      conversation: {
        namespaced: true,
        getters: { getIsCreating: () => false },
      },
      appConfig: {
        namespaced: true,
        getters: { getIsUpdatingRoute: () => false },
      },
      campaign: {
        namespaced: true,
        getters: { getActiveCampaign: () => ({}) },
      },
      contacts: { namespaced: true, getters: { getCurrentUser: () => ({}) } },
    },
  });

const campo = extra => ({
  name: 'tipo',
  label: 'Tipo',
  type: 'text',
  enabled: true,
  required: false,
  ...extra,
});

const montar = fields => {
  global.chatwootWebChannel = {
    preChatFormEnabled: true,
    preChatFormOptions: { pre_chat_fields: fields, pre_chat_message: '' },
    enabledFeatures: [],
  };
  return mount(Form, {
    props: { options: { preChatFields: fields, preChatMessage: '' } },
    global: {
      plugins: [store()],
      mocks: { $t: key => key },
      stubs: {
        FormKit: {
          name: 'FormKit',
          props: ['name', 'label', 'errors', 'help'],
          template: '<div class="fk" :data-name="name"><slot /></div>',
        },
        CustomButton: { template: '<button><slot /></button>' },
        Spinner: true,
      },
    },
  });
};

const nomesRenderizados = wrapper =>
  wrapper
    .findAll('.fk')
    .map(n => n.attributes('data-name'))
    .filter(Boolean);

describe('3.15 na junção — Form.vue como casca', () => {
  afterEach(() => {
    delete global.chatwootWebChannel;
  });

  describe('show_if governa o que é RENDERIZADO', () => {
    const fields = [
      campo(),
      campo({
        name: 'cnpj',
        label: 'CNPJ',
        show_if: { field: 'tipo', operator: 'is', value: 'empresa' },
      }),
    ];

    it('o condicional não é montado enquanto a condição não é satisfeita', async () => {
      const wrapper = montar(fields);
      await wrapper.vm.$nextTick();

      expect(nomesRenderizados(wrapper)).toContain('tipo');
      expect(nomesRenderizados(wrapper)).not.toContain('cnpj');
    });

    it('aparece quando é satisfeita — o aceite literal, na tela', async () => {
      const wrapper = montar(fields);
      wrapper.vm.formValues = { tipo: 'empresa' };
      await wrapper.vm.$nextTick();

      expect(nomesRenderizados(wrapper)).toContain('cnpj');
    });

    it('e volta a sumir quando a resposta do gatilho muda', async () => {
      const wrapper = montar(fields);
      wrapper.vm.formValues = { tipo: 'empresa' };
      await wrapper.vm.$nextTick();
      expect(nomesRenderizados(wrapper)).toContain('cnpj');

      wrapper.vm.formValues = { tipo: 'pessoa' };
      await wrapper.vm.$nextTick();
      expect(nomesRenderizados(wrapper)).not.toContain('cnpj');
    });
  });

  describe('campo escondido não viaja no envio', () => {
    it('valor preenchido ANTES de esconder não é emitido', async () => {
      // O caso real: o visitante responde "empresa", digita o e-mail, muda para
      // "pessoa". O e-mail sumiu da tela — não pode ir junto assim mesmo.
      const wrapper = montar([
        campo(),
        campo({
          name: 'emailAddress',
          label: 'E-mail',
          show_if: { field: 'tipo', operator: 'is', value: 'empresa' },
        }),
      ]);
      wrapper.vm.formValues = {
        tipo: 'empresa',
        emailAddress: 'a@b.com',
        message: 'oi',
      };
      await wrapper.vm.$nextTick();

      wrapper.vm.formValues = { ...wrapper.vm.formValues, tipo: 'pessoa' };
      await wrapper.vm.$nextTick();
      wrapper.vm.onSubmit();

      const [[payload]] = wrapper.emitted('submitPreChat');
      expect(payload.emailAddress).toBeUndefined();
      expect(payload.message).toBe('oi');
    });

    it('campo visível continua sendo emitido normalmente', async () => {
      const wrapper = montar([
        campo({ name: 'emailAddress', label: 'E-mail' }),
      ]);
      wrapper.vm.formValues = { emailAddress: 'a@b.com', message: 'oi' };
      await wrapper.vm.$nextTick();
      wrapper.vm.onSubmit();

      const [[payload]] = wrapper.emitted('submitPreChat');
      expect(payload.emailAddress).toBe('a@b.com');
    });
  });

  describe('mask aplica enquanto digita', () => {
    it('cpf vira formatado no próprio formValues', async () => {
      const wrapper = montar([
        campo({ name: 'doc', label: 'CPF', mask: 'cpf' }),
      ]);
      wrapper.vm.formValues = { doc: '52998224725' };
      await wrapper.vm.$nextTick();

      expect(wrapper.vm.formValues.doc).toBe('529.982.247-25');
    });

    it('a máscara é estável: reaplicar não muda mais nada', async () => {
      const wrapper = montar([
        campo({ name: 'doc', label: 'CPF', mask: 'cpf' }),
      ]);
      wrapper.vm.formValues = { doc: '52998224725' };
      await wrapper.vm.$nextTick();
      const primeira = wrapper.vm.formValues.doc;
      wrapper.vm.applyFieldMasks();
      await wrapper.vm.$nextTick();

      expect(wrapper.vm.formValues.doc).toBe(primeira);
    });
  });

  describe('erro específico por campo, e só depois do blur', () => {
    const comValidador = () =>
      montar([campo({ name: 'doc', label: 'CPF', validator: 'cpf' })]);

    it('campo intocado NÃO mostra erro, mesmo com valor inválido', async () => {
      const wrapper = comValidador();
      wrapper.vm.formValues = { doc: '529.982.247-26' };
      await wrapper.vm.$nextTick();

      expect(
        wrapper.vm.delegatedErrors({ name: 'doc', validator: 'cpf' })
      ).toEqual([]);
    });

    it('depois do blur, o erro é o do CPF — não a mensagem genérica', async () => {
      const wrapper = comValidador();
      wrapper.vm.formValues = { doc: '529.982.247-26' };
      wrapper.vm.markTouched('doc');
      await wrapper.vm.$nextTick();

      expect(
        wrapper.vm.delegatedErrors({ name: 'doc', validator: 'cpf' })
      ).toEqual(['PRE_CHAT_FORM.VALIDATION.CPF']);
    });

    it('CPF válido não produz erro depois do blur', async () => {
      const wrapper = comValidador();
      wrapper.vm.formValues = { doc: '529.982.247-25' };
      wrapper.vm.markTouched('doc');
      await wrapper.vm.$nextTick();

      expect(
        wrapper.vm.delegatedErrors({ name: 'doc', validator: 'cpf' })
      ).toEqual([]);
    });
  });

  describe('step — só a etapa corrente é montada', () => {
    const emDuasEtapas = [
      campo({ name: 'a', label: 'A', step: 1 }),
      campo({ name: 'b', label: 'B', step: 2 }),
    ];

    it('começa na etapa 1, sem a etapa 2 E sem o campo de mensagem', async () => {
      const wrapper = montar(emDuasEtapas);
      await wrapper.vm.$nextTick();

      // A mensagem é o que ABRE a conversa: pedir texto livre na etapa 1 de um
      // formulário de 2 etapas inverte a ordem — responde-se antes de saber o
      // que ainda vem.
      expect(nomesRenderizados(wrapper)).toEqual(['a']);
      expect(wrapper.vm.isLastStep).toBe(false);
    });

    it('avança e, na última etapa, a mensagem entra junto', async () => {
      const wrapper = montar(emDuasEtapas);
      wrapper.vm.goToNextStep();
      await wrapper.vm.$nextTick();

      expect(wrapper.vm.currentStep).toBe(2);
      expect(wrapper.vm.isLastStep).toBe(true);
      expect(nomesRenderizados(wrapper)).toEqual(['b', 'message']);
    });

    it('sem etapas, tudo e a mensagem aparecem de uma vez (o comportamento de hoje)', async () => {
      const wrapper = montar([campo({ name: 'a', label: 'A' })]);
      await wrapper.vm.$nextTick();

      expect(wrapper.vm.hasMultipleSteps).toBe(false);
      expect(nomesRenderizados(wrapper)).toEqual(['a', 'message']);
    });

    it('NÃO avança com obrigatório vazio na etapa corrente', async () => {
      const wrapper = montar([
        campo({ name: 'a', label: 'A', step: 1, required: true }),
        campo({ name: 'b', label: 'B', step: 2 }),
      ]);
      wrapper.vm.goToNextStep();
      await wrapper.vm.$nextTick();

      expect(wrapper.vm.currentStep).toBe(1);
    });

    it('NÃO avança com erro de formato na etapa corrente', async () => {
      const wrapper = montar([
        campo({ name: 'doc', label: 'CPF', step: 1, validator: 'cpf' }),
        campo({ name: 'b', label: 'B', step: 2 }),
      ]);
      wrapper.vm.formValues = { doc: '529.982.247-26' };
      await wrapper.vm.$nextTick();
      wrapper.vm.goToNextStep();
      await wrapper.vm.$nextTick();

      expect(wrapper.vm.currentStep).toBe(1);
    });

    it('aviso suave (junk) NÃO impede avançar — o bloqueio é suave por decisão do 3.13', async () => {
      const wrapper = montar([
        campo({ name: 'nome', label: 'Nome', step: 1, validator: 'junk_name' }),
        campo({ name: 'b', label: 'B', step: 2 }),
      ]);
      wrapper.vm.formValues = { nome: 'bcdfg' };
      await wrapper.vm.$nextTick();
      wrapper.vm.goToNextStep();
      await wrapper.vm.$nextTick();

      expect(wrapper.vm.currentStep).toBe(2);
    });

    it('etapa que some por show_if devolve o visitante para uma etapa que existe', async () => {
      const wrapper = montar([
        campo({ name: 'tipo', label: 'Tipo', step: 1 }),
        campo({
          name: 'cnpj',
          label: 'CNPJ',
          step: 2,
          show_if: { field: 'tipo', operator: 'is', value: 'empresa' },
        }),
      ]);
      wrapper.vm.formValues = { tipo: 'empresa' };
      await wrapper.vm.$nextTick();
      wrapper.vm.goToNextStep();
      await wrapper.vm.$nextTick();
      expect(wrapper.vm.currentStep).toBe(2);

      // O visitante volta e troca a resposta: a etapa 2 deixa de existir.
      wrapper.vm.formValues = { tipo: 'pessoa' };
      await wrapper.vm.$nextTick();

      expect(wrapper.vm.currentStep).toBe(1);
      expect(wrapper.vm.visibleSteps).toEqual([1]);
    });
  });
});
