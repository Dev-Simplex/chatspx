import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { h } from 'vue';

import { MESSAGE_TYPES, resolveMessageType } from '../index';
import AgentMessageBubble from 'widget/components/AgentMessageBubble.vue';
import TextContent from '../TextContent.vue';
import EmailContent from '../EmailContent.vue';
import IntegrationsContent from '../IntegrationsContent.vue';
import SelectContent from '../SelectContent.vue';
import FormContent from '../FormContent.vue';
import CardsContent from '../CardsContent.vue';
import ArticleContent from '../ArticleContent.vue';
import CsatContent from '../CsatContent.vue';

describe('registry de content_type', () => {
  // Régua do contrato: os 8 tipos que o widget desenha, copiados do enum
  // `content_type` de `app/models/message.rb`. Um tipo que suma ou nasça
  // sem querer reprova aqui antes de chegar na tela do visitante.
  it('mapeia exatamente os 8 tipos suportados, cada um no seu componente', () => {
    expect(MESSAGE_TYPES).toEqual({
      text: TextContent,
      input_email: EmailContent,
      integrations: IntegrationsContent,
      input_select: SelectContent,
      form: FormContent,
      cards: CardsContent,
      article: ArticleContent,
      input_csat: CsatContent,
    });
  });

  describe('resolveMessageType', () => {
    it.each([
      ['text', TextContent],
      ['input_email', EmailContent],
      ['integrations', IntegrationsContent],
      ['input_select', SelectContent],
      ['form', FormContent],
      ['cards', CardsContent],
      ['article', ArticleContent],
      ['input_csat', CsatContent],
    ])('resolve %s', (contentType, expected) => {
      expect(resolveMessageType(contentType)).toBe(expected);
    });

    // Os outros seis valores do enum do backend não têm desenho próprio.
    it.each([
      'input_text',
      'input_textarea',
      'incoming_email',
      'sticker',
      'input_nps',
      'voice_call',
      'um_tipo_que_ainda_nao_existe',
    ])('%s degrada para o texto, não para o vazio', contentType => {
      expect(resolveMessageType(contentType)).toBe(TextContent);
    });

    it.each([[null], [undefined], ['']])(
      'content_type ausente (%s) degrada para o texto',
      contentType => {
        expect(resolveMessageType(contentType)).toBe(TextContent);
      }
    );
  });

  // Este é o aceite do bloco 1.10 executado, não afirmado: o custo de um
  // nono tipo é um componente novo mais uma entrada no mapa. Se algum dia
  // voltar a ser preciso editar `AgentMessageBubble.vue` para acrescentar
  // tipo, o registro abaixo não renderiza e o teste reprova.
  describe('o custo de um 9º tipo', () => {
    const NonoTipo = {
      name: 'NonoTipo',
      props: {
        message: { type: String, default: null },
        messageId: { type: Number, default: null },
        messageContentAttributes: { type: Object, default: () => ({}) },
      },
      emits: ['response'],
      render() {
        return h(
          'button',
          {
            class: 'nono-tipo',
            onClick: () =>
              this.$emit('response', {
                submittedValues: [{ escolha: 'sim' }],
                messageId: this.messageId,
              }),
          },
          `${this.message} · ${this.messageContentAttributes.rotulo}`
        );
      },
    };

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
      // "uma linha no mapa" — literalmente a única coisa que este teste faz
      // antes de esperar que o tipo novo apareça na tela.
      MESSAGE_TYPES.handoff_card = NonoTipo;
    });

    afterEach(() => {
      delete MESSAGE_TYPES.handoff_card;
    });

    it('renderiza sem que AgentMessageBubble.vue seja tocado', () => {
      const wrapper = mount(AgentMessageBubble, {
        props: {
          message: 'Passando para um humano',
          contentType: 'handoff_card',
          messageId: 42,
          messageContentAttributes: { rotulo: 'agora' },
        },
        global: {
          plugins: [store],
          directives: { 'dompurify-html': { mounted: () => {} } },
        },
      });

      const botao = wrapper.find('button.nono-tipo');
      expect(botao.exists()).toBe(true);
      expect(botao.text()).toBe('Passando para um humano · agora');
    });

    it('a resposta do tipo novo chega no store pelo mesmo caminho', async () => {
      const wrapper = mount(AgentMessageBubble, {
        props: {
          message: 'Passando para um humano',
          contentType: 'handoff_card',
          messageId: 42,
          messageContentAttributes: { rotulo: 'agora' },
        },
        global: {
          plugins: [store],
          directives: { 'dompurify-html': { mounted: () => {} } },
        },
      });

      await wrapper.find('button.nono-tipo').trigger('click');

      expect(dispatch).toHaveBeenCalledWith(expect.anything(), {
        submittedValues: [{ escolha: 'sim' }],
        messageId: 42,
      });
    });
  });
});
