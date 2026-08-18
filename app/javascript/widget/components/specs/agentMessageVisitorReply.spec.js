/**
 * Mecanismo da PONTA DE CONTRATO do bloco 4.01 no widget.
 *
 * O backend passou a materializar a resposta do visitante (clique num `input_select`, envio de um
 * `form`) como mensagem `incoming` de verdade, e marca a mensagem estruturada com
 * `content_attributes.reply_message_id`. Sem esta ponta, a tela mostraria DUAS vezes a mesma
 * resposta: o balão local que o widget já desenhava + a mensagem real que chega pela lista.
 *
 * Este spec mede as duas metades:
 *  · com `reply_message_id` → o balão local NÃO é desenhado (quem desenha é a mensagem real);
 *  · sem `reply_message_id` (motor desligado) → comportamento idêntico ao de hoje.
 */
import { shallowMount } from '@vue/test-utils';
import AgentMessage from '../AgentMessage.vue';

const montar = message =>
  shallowMount(AgentMessage, {
    props: { message },
    global: {
      mocks: { $t: k => k },
      stubs: { Avatar: true, MessageReplyButton: true, ReplyToChip: true },
      // A diretiva vem do plugin vue-dompurify-html, registrado só no app real; sem ela o Vue
      // emitiria um warn de diretiva não resolvida a cada mount (ruído, não defeito).
      directives: { 'dompurify-html': {} },
    },
  });

beforeEach(() => {
  window.chatwootWebChannel = {
    enabledFeatures: [],
    avatarUrl: '',
    preChatFormOptions: {},
  };
});

describe('4.01 — o widget não duplica a resposta do visitante', () => {
  const optionMessage = contentAttributes => ({
    id: 10,
    content: 'Confirma?',
    message_type: 3,
    content_type: 'input_select',
    content_attributes: contentAttributes,
  });

  it('desenha o balão local quando o backend NÃO materializou a resposta (motor desligado)', () => {
    const wrapper = montar(
      optionMessage({ submitted_values: [{ title: 'Sim', value: 'yes' }] })
    );

    expect(wrapper.vm.hasRecordedResponse).toBe(true);
    expect(wrapper.findComponent({ name: 'UserMessage' }).exists()).toBe(true);
  });

  it('some com o balão local quando a resposta virou mensagem incoming (reply_message_id)', () => {
    const wrapper = montar(
      optionMessage({
        submitted_values: [{ title: 'Sim', value: 'yes' }],
        reply_message_id: 77,
      })
    );

    expect(wrapper.vm.hasRecordedResponse).toBe(false);
    expect(wrapper.findComponent({ name: 'UserMessage' }).exists()).toBe(false);
  });

  const formMessage = contentAttributes => ({
    id: 11,
    content: 'Seus dados',
    message_type: 3,
    content_type: 'form',
    content_attributes: contentAttributes,
  });

  it('formulário: mantém os balões locais sem reply_message_id', () => {
    const wrapper = montar(
      formMessage({ submitted_values: [{ name: 'nome', value: 'Walisson' }] })
    );

    expect(wrapper.vm.isASubmittedForm).toBe(true);
  });

  it('formulário: não repete os valores quando a resposta virou mensagem incoming', () => {
    const wrapper = montar(
      formMessage({
        submitted_values: [{ name: 'nome', value: 'Walisson' }],
        reply_message_id: 78,
      })
    );

    expect(wrapper.vm.isASubmittedForm).toBe(false);
    expect(wrapper.findComponent({ name: 'UserMessage' }).exists()).toBe(false);
  });
});
