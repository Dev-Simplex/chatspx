/**
 * BLOCO 3.15 — a CASCA, montada de verdade.
 *
 * O spec do helper (`widget/helpers/specs/preChatFieldRules.spec.js`) prova a
 * regra isolada. Este prova a JUNÇÃO — que é onde esta execução já se machucou:
 * o pior defeito da onda foi produtor e consumidor certos sozinhos e errados
 * juntos. Aqui o componente é montado e perguntado o que ele renderiza e o que
 * ele emite.
 */
import { flushPromises, mount } from '@vue/test-utils';
import { plugin, defaultConfig } from '@formkit/vue';
import { createStore } from 'vuex';
import PreChatBody from '../PreChatBody.vue';

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
  return mount(PreChatBody, {
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

describe('3.15 na junção — o corpo do pré-chat, montado de verdade', () => {
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

  describe('o gatilho de LISTA na junção — o que o FormKit realmente guarda', () => {
    // O `select` do pré-chat é montado com as opções indexadas por POSIÇÃO
    // (`getOptions`), então `formValues.tipo` vale '0', nunca 'Empresa'. Quem
    // configura a condicional digita o rótulo, porque é o que está na tela do
    // painel. Esta é a forma REAL do gatilho — e a que o fixture de `type: text`
    // do resto deste arquivo nunca exercitou.
    const comLista = [
      campo({
        name: 'tipo',
        label: 'Tipo',
        type: 'list',
        values: ['Empresa', 'Pessoa física'],
      }),
      campo({
        name: 'cnpj',
        label: 'CNPJ',
        show_if: { field: 'tipo', operator: 'is', value: 'Empresa' },
      }),
    ];

    it('escolher "Empresa" (posição 0) revela o dependente', async () => {
      const wrapper = montar(comLista);
      wrapper.vm.formValues = { tipo: '0' };
      await wrapper.vm.$nextTick();

      expect(nomesRenderizados(wrapper)).toContain('cnpj');
    });

    it('escolher "Pessoa física" (posição 1) mantém o dependente escondido', async () => {
      const wrapper = montar(comLista);
      wrapper.vm.formValues = { tipo: '1' };
      await wrapper.vm.$nextTick();

      expect(nomesRenderizados(wrapper)).not.toContain('cnpj');
    });

    it('o atributo enviado é o RÓTULO, não a posição — a mesma resolução', async () => {
      const wrapper = montar([
        campo({
          name: 'tipo',
          label: 'Tipo',
          type: 'list',
          field_type: 'contact_attribute',
          values: ['Empresa', 'Pessoa física'],
        }),
      ]);
      wrapper.vm.formValues = { tipo: '0', message: 'oi' };
      await wrapper.vm.$nextTick();
      wrapper.vm.onSubmit();

      const [[payload]] = wrapper.emitted('submitPreChat');
      expect(payload.contactCustomAttributes.tipo).toBe('Empresa');
    });
  });

  describe('o gatilho de CAIXA na junção', () => {
    const comCaixa = operator => [
      campo({ name: 'aceito', label: 'Aceito', type: 'checkbox' }),
      campo({
        name: 'cnpj',
        label: 'CNPJ',
        show_if: { field: 'aceito', operator, value: 'sim' },
      }),
    ];

    it('caixa DESMARCADA não satisfaz `filled` — `false` não é conteúdo', async () => {
      const wrapper = montar(comCaixa('filled'));
      wrapper.vm.formValues = { aceito: false };
      await wrapper.vm.$nextTick();

      expect(nomesRenderizados(wrapper)).not.toContain('cnpj');
    });

    it('caixa MARCADA satisfaz `filled`', async () => {
      const wrapper = montar(comCaixa('filled'));
      wrapper.vm.formValues = { aceito: true };
      await wrapper.vm.$nextTick();

      expect(nomesRenderizados(wrapper)).toContain('cnpj');
    });

    it('`is sim` casa com a caixa marcada, e só com ela', async () => {
      const wrapper = montar(comCaixa('is'));
      wrapper.vm.formValues = { aceito: false };
      await wrapper.vm.$nextTick();
      expect(nomesRenderizados(wrapper)).not.toContain('cnpj');

      wrapper.vm.formValues = { aceito: true };
      await wrapper.vm.$nextTick();
      expect(nomesRenderizados(wrapper)).toContain('cnpj');
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

/**
 * O ACEITE, SEM DUBLÊ NENHUM.
 *
 * Tudo acima usa um stub de `FormKit` — rápido, mas ele responde o que a gente
 * mandou responder. O defeito que este bloco fecha nasceu exatamente aí: o valor
 * que o FormKit GUARDA num `<select>` (a posição) não é o que o fixture de
 * `type: 'text'` fingia guardar (o rótulo), e por isso 61 testes verdes não
 * viram o campo condicional deixar de aparecer.
 *
 * Aqui o FormKit é o de verdade, o `<select>` é um `<select>` do DOM, e quem
 * escolhe a opção é `setValue` — o mesmo caminho do visitante.
 */
describe('3.15 — o aceite com o FormKit de verdade', () => {
  const montarReal = fields => {
    global.chatwootWebChannel = {
      preChatFormEnabled: true,
      preChatFormOptions: { pre_chat_fields: fields, pre_chat_message: '' },
      enabledFeatures: [],
    };
    return mount(PreChatBody, {
      props: { options: { preChatFields: fields, preChatMessage: '' } },
      global: {
        plugins: [store(), [plugin, defaultConfig()]],
        mocks: { $t: key => key },
        stubs: { CustomButton: { template: '<button><slot /></button>' } },
        directives: { 'dompurify-html': () => {} },
      },
    });
  };

  /**
   * O FormKit comita o valor em etapas (evento → nó → modelo → render), e sob
   * carga um `flushPromises` só nem sempre alcança a última. Esperar o MODELO do
   * formulário refletir a resposta torna a medição determinística: o que vem
   * depois dela é render, e um flush dá conta.
   *
   * Sem isto o teste fica intermitente — e teste intermitente ensina o time a
   * ignorar vermelho, que é pior do que não ter teste.
   */
  const responder = async (wrapper, seletor, nome, valor) => {
    await wrapper.find(seletor).setValue(valor);
    await vi.waitFor(() =>
      expect(String(wrapper.vm.formValues[nome])).toBe(String(valor))
    );
    await flushPromises();
  };

  afterEach(() => {
    delete global.chatwootWebChannel;
  });

  it('escolher a opção do gatilho REVELA o campo condicional', async () => {
    const wrapper = montarReal([
      campo({
        name: 'tipo',
        label: 'Tipo',
        type: 'list',
        values: ['Empresa', 'Pessoa física'],
      }),
      campo({
        name: 'cnpj',
        label: 'CNPJ',
        show_if: { field: 'tipo', operator: 'is', value: 'Empresa' },
      }),
    ]);
    await flushPromises();
    expect(wrapper.find('select').exists()).toBe(true);

    // O `<select>` do pré-chat não tem opção vazia, então ele nasce respondido
    // na primeira — é comportamento do controle, não deste bloco. Por isso a
    // medição começa escolhendo a OUTRA opção: é a partir dela que dá para ver
    // o campo aparecer.
    await responder(wrapper, 'select', 'tipo', '1');
    expect(wrapper.text()).not.toContain('CNPJ');

    // "Empresa" é a posição 0 — é isso que o `<select>` entrega ao formulário,
    // e é comparando ISSO com o rótulo que a condicional errava antes.
    await responder(wrapper, 'select', 'tipo', '0');
    expect(wrapper.text()).toContain('CNPJ');

    // E some de novo ao trocar a resposta.
    await responder(wrapper, 'select', 'tipo', '1');
    expect(wrapper.text()).not.toContain('CNPJ');
  });

  it('marcar a caixa do gatilho REVELA o campo condicional', async () => {
    const wrapper = montarReal([
      campo({ name: 'aceito', label: 'Aceito', type: 'checkbox' }),
      campo({
        name: 'cnpj',
        label: 'CNPJ',
        show_if: { field: 'aceito', operator: 'filled' },
      }),
    ]);
    await flushPromises();

    // Desmarcada, o valor guardado é `false` — e `String(false)` tem cinco
    // letras. Era este o caminho pelo qual `filled` dava verdadeiro.
    expect(wrapper.find('input[type="checkbox"]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('CNPJ');

    await responder(wrapper, 'input[type="checkbox"]', 'aceito', true);

    expect(wrapper.text()).toContain('CNPJ');
  });

  it('o erro específico do campo aparece depois do blur, e é o do validador', async () => {
    const wrapper = montarReal([
      campo({ name: 'doc', label: 'CPF', validator: 'cpf' }),
    ]);
    await flushPromises();

    await responder(wrapper, 'input[name="doc"]', 'doc', '529.982.247-26');
    // Intocado: nada de erro — acusar formato no terceiro dígito é ruído.
    expect(wrapper.text()).not.toContain('PRE_CHAT_FORM.VALIDATION.CPF');

    await wrapper.find('input[name="doc"]').trigger('blur');
    await vi.waitFor(() => expect(wrapper.vm.touchedFields).toContain('doc'));
    await flushPromises();

    expect(wrapper.text()).toContain('PRE_CHAT_FORM.VALIDATION.CPF');
  });
});
