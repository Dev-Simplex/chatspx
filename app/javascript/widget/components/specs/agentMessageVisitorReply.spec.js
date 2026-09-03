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
 *
 * ── Por que ele monta e olha o DOM, e não lê `wrapper.vm` (bloco 2.02) ────────
 *
 * A versão anterior lia os computados `hasRecordedResponse`/`isASubmittedForm` de
 * `AgentMessage`. Isso amarrava o teste ao lugar onde a decisão está escrita —
 * e a decisão mudou de arquivo quando as duas linhas viraram `MessageRow`. Uma
 * asserção sobre `.user-message-wrap` na árvore renderizada mede o EFEITO que o
 * bloco 4.01 promete: o balão local existe, ou não existe.
 */
import { mount } from '@vue/test-utils';
import AgentMessage from '../AgentMessage.vue';

const montar = message =>
  mount(AgentMessage, {
    props: { message },
    global: {
      mocks: { $t: k => k },
      stubs: {
        Avatar: true,
        MessageReplyButton: true,
        ReplyToChip: true,
        AgentMessageBubble: true,
        UserMessageBubble: true,
        DragWrapper: true,
        FluentIcon: true,
      },
      // A diretiva vem do plugin vue-dompurify-html, registrado só no app real; sem ela o Vue
      // emitiria um warn de diretiva não resolvida a cada mount (ruído, não defeito).
      directives: { 'dompurify-html': {} },
    },
  });

/** Quantos balões LOCAIS de visitante a linha do agente desenhou. */
const baloesLocais = wrapper => wrapper.findAll('.user-message-wrap').length;

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

    expect(baloesLocais(wrapper)).toBe(1);
  });

  it('some com o balão local quando a resposta virou mensagem incoming (reply_message_id)', () => {
    const wrapper = montar(
      optionMessage({
        submitted_values: [{ title: 'Sim', value: 'yes' }],
        reply_message_id: 77,
      })
    );

    expect(baloesLocais(wrapper)).toBe(0);
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
      formMessage({
        submitted_values: [
          { name: 'nome', value: 'Walisson' },
          { name: 'email', value: 'w@exemplo.com' },
        ],
      })
    );

    // Um balão por valor enviado — e é isto que a segunda metade do aceite
    // proíbe de aparecer quando o backend já materializou a resposta.
    expect(baloesLocais(wrapper)).toBe(2);
  });

  it('formulário: não repete os valores quando a resposta virou mensagem incoming', () => {
    const wrapper = montar(
      formMessage({
        submitted_values: [
          { name: 'nome', value: 'Walisson' },
          { name: 'email', value: 'w@exemplo.com' },
        ],
        reply_message_id: 78,
      })
    );

    expect(baloesLocais(wrapper)).toBe(0);
  });
});
