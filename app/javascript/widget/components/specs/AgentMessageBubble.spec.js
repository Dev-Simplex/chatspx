import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';

import AgentMessageBubble from '../AgentMessageBubble.vue';
import ChatCard from 'shared/components/ChatCard.vue';
import ChatForm from 'shared/components/ChatForm.vue';
import ChatOptions from 'shared/components/ChatOptions.vue';
import CustomerSatisfaction from 'shared/components/CustomerSatisfaction.vue';
import ChatArticle from '../template/Article.vue';
import EmailInput from '../template/EmailInput.vue';
import IntegrationCard from '../template/IntegrationCard.vue';

// Régua de comportamento do bloco 1.10.
//
// Estas asserções foram escritas contra a implementação ANTIGA (a cadeia de
// `v-if` com o `!isCards` duplicado) e valem palavra por palavra depois do
// registry. É isso que as torna régua e não espelho da implementação: se a
// refatoração mudar um pixel de qualquer um dos 8 tipos, um destes reprova.

describe('AgentMessageBubble', () => {
  let dispatch;
  let store;

  beforeEach(() => {
    dispatch = vi.fn();
    store = createStore({
      modules: {
        message: { namespaced: true, actions: { update: dispatch } },
        appConfig: {
          namespaced: true,
          getters: { getWidgetColor: () => '#1f93ff' },
        },
      },
    });
  });

  // Montagem profunda de propósito: o que esta régua mede é a ESTRUTURA que
  // chega ao DOM atravessando o registry. Só os componentes folha — que falam
  // com API, vuelidate e Dyte — são stubados; se eles fossem reais, o teste
  // mediria a implementação deles, não a desta bolha.
  const mountBubble = (props = {}) =>
    mount(AgentMessageBubble, {
      props: {
        message: 'Olá, tudo bem?',
        contentType: 'text',
        messageType: 1,
        messageId: 7,
        messageContentAttributes: {},
        ...props,
      },
      global: {
        plugins: [store],
        directives: { 'dompurify-html': { mounted: () => {} } },
        stubs: {
          EmailInput: true,
          IntegrationCard: true,
          ChatOptions: true,
          ChatForm: true,
          ChatCard: true,
          ChatArticle: true,
          CustomerSatisfaction: true,
        },
      },
    });

  // A bolha de texto é a `div.chat-bubble.agent`; os tipos ricos que a
  // substituem não podem deixá-la na tela junto.
  const hasTextBubble = wrapper => wrapper.find('.chat-bubble.agent').exists();

  it('sempre embrulha o conteúdo em .chat-bubble-wrap', () => {
    expect(mountBubble().find('.chat-bubble-wrap').exists()).toBe(true);
  });

  it('message-type, que nenhum tipo consome, não desce para o DOM', () => {
    // O call-site (`AgentMessage.vue`) continua passando `:message-type`, e
    // o registry não o repassa a ninguém: o computed `isTemplate` que o lia
    // nunca chegou a ser usado no template. Como a prop deixou de ser
    // declarada, sem `inheritAttrs: false` ela viraria atributo solto — o
    // mesmo defeito do `meeting-data`, recriado na saída.
    expect(mountBubble({ messageType: 3 }).attributes('message-type')).toBe(
      undefined
    );
  });

  describe('os 8 tipos suportados', () => {
    it('text: só a bolha de texto, nenhum tipo rico', () => {
      const wrapper = mountBubble({ contentType: 'text' });

      expect(hasTextBubble(wrapper)).toBe(true);
      expect(wrapper.findComponent(EmailInput).exists()).toBe(false);
      expect(wrapper.findComponent(IntegrationCard).exists()).toBe(false);
      expect(wrapper.findComponent(ChatOptions).exists()).toBe(false);
      expect(wrapper.findComponent(ChatForm).exists()).toBe(false);
      expect(wrapper.findComponent(ChatCard).exists()).toBe(false);
      expect(wrapper.findComponent(ChatArticle).exists()).toBe(false);
      expect(wrapper.findComponent(CustomerSatisfaction).exists()).toBe(false);
    });

    it('input_email: EmailInput DENTRO da bolha de texto', () => {
      const wrapper = mountBubble({
        contentType: 'input_email',
        messageContentAttributes: { submitted_email: '' },
      });

      expect(hasTextBubble(wrapper)).toBe(true);
      const input = wrapper.findComponent(EmailInput);
      expect(input.exists()).toBe(true);
      // Dentro da bolha, não irmão dela — é o que difere estes dois tipos
      // dos outros seis, e o que a refatoração tinha que preservar.
      expect(
        wrapper.find('.chat-bubble.agent').element.contains(input.element)
      ).toBe(true);
      expect(input.props('messageId')).toBe(7);
      expect(input.props('messageContentAttributes')).toEqual({
        submitted_email: '',
      });
    });

    it('integrations: IntegrationCard DENTRO da bolha de texto', () => {
      const wrapper = mountBubble({
        contentType: 'integrations',
        messageContentAttributes: { data: { room_name: 'sala-1' } },
      });

      expect(hasTextBubble(wrapper)).toBe(true);
      const card = wrapper.findComponent(IntegrationCard);
      expect(card.exists()).toBe(true);
      expect(
        wrapper.find('.chat-bubble.agent').element.contains(card.element)
      ).toBe(true);
      expect(card.props('messageId')).toBe(7);
    });

    it('integrations: nenhuma prop morta sobra no DOM', () => {
      const wrapper = mountBubble({
        contentType: 'integrations',
        messageContentAttributes: { data: { room_name: 'sala-1' } },
      });

      // ACHADO do 1.10 — `AgentMessageBubble.vue:113` passava
      // `:meeting-data="messageContentAttributes.data"` e NENHUM componente
      // declara ou lê essa prop: o IntegrationCard busca o token pela API a
      // partir do `messageId` (`joinTheCall`). O dado não chegava a lugar
      // nenhum; virava atributo solto no DOM do cartão. Nada no repositório
      // seleciona por ele (`grep meeting-data` = só a linha que o emitia).
      expect(
        wrapper.findComponent(IntegrationCard).attributes('meeting-data')
      ).toBeUndefined();
    });

    it('input_select: ChatOptions no lugar da bolha de texto', () => {
      const wrapper = mountBubble({
        contentType: 'input_select',
        message: 'Escolha uma opção',
        messageContentAttributes: {
          items: [{ title: 'A', value: 'a' }],
        },
      });

      expect(hasTextBubble(wrapper)).toBe(false);
      const options = wrapper.findComponent(ChatOptions);
      expect(options.props('title')).toBe('Escolha uma opção');
      expect(options.props('options')).toEqual([{ title: 'A', value: 'a' }]);
      expect(options.props('hideFields')).toBe(false);
    });

    it('input_select já respondido: hideFields vira true', () => {
      const wrapper = mountBubble({
        contentType: 'input_select',
        messageContentAttributes: {
          items: [{ title: 'A', value: 'a' }],
          submitted_values: [{ title: 'A', value: 'a' }],
        },
      });

      expect(wrapper.findComponent(ChatOptions).props('hideFields')).toBe(true);
    });

    it('form: ChatForm no lugar da bolha de texto', () => {
      const wrapper = mountBubble({
        contentType: 'form',
        messageContentAttributes: {
          items: [{ name: 'email', label: 'E-mail' }],
          button_label: 'Enviar',
        },
      });

      expect(hasTextBubble(wrapper)).toBe(false);
      const form = wrapper.findComponent(ChatForm);
      expect(form.props('items')).toEqual([{ name: 'email', label: 'E-mail' }]);
      expect(form.props('buttonLabel')).toBe('Enviar');
    });

    it('form já respondido: NADA renderiza — nem formulário, nem bolha', () => {
      const wrapper = mountBubble({
        contentType: 'form',
        messageContentAttributes: {
          items: [{ name: 'email' }],
          submitted_values: [{ name: 'email', value: 'a@b.c' }],
        },
      });

      expect(hasTextBubble(wrapper)).toBe(false);
      expect(wrapper.findComponent(ChatForm).exists()).toBe(false);
    });

    it('cards: um ChatCard por item, com os campos mapeados', () => {
      const wrapper = mountBubble({
        contentType: 'cards',
        messageContentAttributes: {
          items: [
            {
              title: 'Plano A',
              description: 'desc A',
              media_url: 'https://ex.com/a.png',
              actions: [{ type: 'link', text: 'ver' }],
            },
            { title: 'Plano B', description: 'desc B', actions: [] },
          ],
        },
      });

      expect(hasTextBubble(wrapper)).toBe(false);
      const cards = wrapper.findAllComponents(ChatCard);
      expect(cards).toHaveLength(2);
      expect(cards[0].props('title')).toBe('Plano A');
      expect(cards[0].props('description')).toBe('desc A');
      expect(cards[0].props('mediaUrl')).toBe('https://ex.com/a.png');
      expect(cards[0].props('actions')).toEqual([
        { type: 'link', text: 'ver' },
      ]);
      expect(cards[1].props('title')).toBe('Plano B');
    });

    it('article: ChatArticle com os itens', () => {
      const items = [{ title: 'Como faço X', link: 'https://ex.com/x' }];
      const wrapper = mountBubble({
        contentType: 'article',
        messageContentAttributes: { items },
      });

      expect(hasTextBubble(wrapper)).toBe(false);
      expect(wrapper.findComponent(ChatArticle).props('items')).toEqual(items);
    });

    it('input_csat: CustomerSatisfaction com display_type e submitted_values', () => {
      const wrapper = mountBubble({
        contentType: 'input_csat',
        message: 'Como foi o atendimento?',
        messageContentAttributes: {
          display_type: 'emoji',
          submitted_values: { csat_survey_response: { rating: 5 } },
        },
      });

      expect(hasTextBubble(wrapper)).toBe(false);
      const csat = wrapper.findComponent(CustomerSatisfaction);
      expect(csat.props('displayType')).toBe('emoji');
      expect(csat.props('message')).toBe('Como foi o atendimento?');
      expect(csat.props('messageId')).toBe(7);
      expect(csat.props('messageContentAttributes')).toEqual({
        csat_survey_response: { rating: 5 },
      });
    });
  });

  describe('content_type que o widget não conhece', () => {
    // O backend tem 14 valores no enum de content_type; o widget desenha 8.
    // Os outros seis caíam na bolha de texto e têm que continuar caindo:
    // degradar para o texto é o comportamento correto, sumir não é.
    it.each([
      'input_text',
      'input_textarea',
      'incoming_email',
      'sticker',
      'input_nps',
      'voice_call',
    ])('%s degrada para a bolha de texto', contentType => {
      const wrapper = mountBubble({ contentType });

      expect(hasTextBubble(wrapper)).toBe(true);
      expect(wrapper.findComponent(ChatOptions).exists()).toBe(false);
      expect(wrapper.findComponent(ChatCard).exists()).toBe(false);
    });

    it('contentType null degrada para a bolha de texto', () => {
      expect(hasTextBubble(mountBubble({ contentType: null }))).toBe(true);
    });
  });

  describe('respostas do visitante', () => {
    it('opção escolhida vira message/update com o valor selecionado', async () => {
      const wrapper = mountBubble({
        contentType: 'input_select',
        messageContentAttributes: { items: [{ title: 'A', value: 'a' }] },
      });

      // O nome real que o ChatOptions emite é camelCase (`emits: ['optionSelect']`);
      // o `@option-select` do template é o alias que o compilador normaliza.
      wrapper.findComponent(ChatOptions).vm.$emit('optionSelect', {
        title: 'A',
        value: 'a',
      });

      expect(dispatch).toHaveBeenCalledWith(expect.anything(), {
        submittedValues: [{ title: 'A', value: 'a' }],
        messageId: 7,
      });
    });

    it('formulário enviado vira lista de {name, value}, não o objeto cru', () => {
      const wrapper = mountBubble({
        contentType: 'form',
        messageContentAttributes: { items: [{ name: 'email' }] },
      });

      wrapper.findComponent(ChatForm).vm.$emit('submit', {
        email: 'a@b.c',
        cidade: 'Marília',
      });

      expect(dispatch).toHaveBeenCalledWith(expect.anything(), {
        submittedValues: [
          { name: 'email', value: 'a@b.c' },
          { name: 'cidade', value: 'Marília' },
        ],
        messageId: 7,
      });
    });
  });
});
