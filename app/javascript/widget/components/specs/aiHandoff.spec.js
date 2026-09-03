/**
 * BLOCO 4.09 na JUNÇÃO — as três marcações, com os componentes montados.
 *
 * Aceite (§2.2): "Simulando handoff, as 3 aparecem; simulando volta à IA, as 3
 * também." As três são **sistema** (marcador no fluxo), **header** (quem atende
 * agora) e **bolha** (o rótulo colado na mensagem).
 *
 * A quarta asserção do aceite — "nunca roxo como marcador" — é de APARÊNCIA e
 * está em `specs/browser/handoff-mark-color.check.mjs`, medida em Chromium. Um
 * teste que inspecionasse a folha de estilo e concluísse passaria com o defeito
 * vivo.
 */
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ConversationWrap from '../ConversationWrap.vue';
import ChatHeader from '../ChatHeader.vue';
import AiHandoffMark from '../AiHandoffMark.vue';
import { ATTENDANT, currentAttendant } from 'widget/helpers/aiIdentity';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import en from 'widget/i18n/locale/en.json';

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  fallbackLocale: 'en',
  messages: { pt_BR: ptBR, en },
});

const daIA = id => ({
  id,
  message_type: 1,
  content: 'Posso ajudar?',
  sender: { type: 'agent_bot', name: 'Bot' },
});
const doHumano = id => ({
  id,
  message_type: 1,
  content: 'Oi, aqui é a Marina',
  sender: { type: 'user', name: 'Marina' },
});
const doVisitante = id => ({
  id,
  message_type: 0,
  content: 'oi',
  sender: null,
});

const montarConversa = (messages, { isAgentTyping = false } = {}) => {
  const store = createStore({
    modules: {
      conversation: {
        namespaced: true,
        getters: {
          getEarliestMessage: () => ({}),
          getLastMessage: () => messages[messages.length - 1] || {},
          getAllMessagesLoaded: () => true,
          getIsFetchingList: () => false,
          getConversationSize: () => messages.length,
          getIsAgentTyping: () => isAgentTyping,
        },
      },
      conversationAttributes: {
        namespaced: true,
        getters: { getConversationParams: () => ({ status: 'open' }) },
      },
      appConfig: {
        namespaced: true,
        getters: { darkMode: () => 'light' },
      },
    },
  });

  return mount(ConversationWrap, {
    props: { groupedMessages: [{ date: 'hoje', messages }] },
    global: {
      plugins: [store, i18n],
      stubs: {
        ChatMessage: {
          props: ['message'],
          template:
            '<div class="cm" :data-id="message.id" :data-attendant="message.attendant" />',
        },
        // `WDateSeparator` e não `DateSeparator`: o bloco 2.04 trocou o
        // separador compartilhado por um primitivo do widget (a pílula). Com o
        // nome antigo o stub não pega, o componente real monta e `formatDate`
        // estoura com "Invalid time value" na data simbólica `'hoje'` deste
        // arquivo — que não é data e não precisa ser, porque o separador não é
        // o objeto deste teste.
        WDateSeparator: true,
        Spinner: true,
        AgentTypingBubble: true,
      },
    },
  });
};

const montarCabecalho = attendant =>
  mount(ChatHeader, {
    props: { title: 'Suporte', attendant },
    global: {
      plugins: [i18n],
      stubs: {
        FluentIcon: true,
        HeaderActions: true,
        AvailabilityContainer: true,
      },
    },
  });

describe('4.09 — as três marcações, montadas', () => {
  describe('MARCAÇÃO 1 (sistema) — o marcador no fluxo da conversa', () => {
    it('conversa só com IA não tem marcador — ninguém foi transferido', () => {
      const wrapper = montarConversa([daIA(1), doVisitante(2), daIA(3)]);
      expect(wrapper.findAllComponents(AiHandoffMark)).toHaveLength(0);
    });

    it('HANDOFF: quando a equipe entra, o marcador aparece com o texto certo', () => {
      const wrapper = montarConversa([daIA(1), doVisitante(2), doHumano(3)]);
      const marcas = wrapper.findAllComponents(AiHandoffMark);

      expect(marcas).toHaveLength(1);
      expect(marcas[0].props('kind')).toBe('to_human');
      expect(marcas[0].text()).toBe('A partir daqui, quem responde é a equipe');
    });

    it('VOLTA: quando o assistente retoma, o marcador aparece de novo', () => {
      const wrapper = montarConversa([daIA(1), doHumano(2), daIA(3)]);
      const marcas = wrapper.findAllComponents(AiHandoffMark);

      expect(marcas).toHaveLength(2);
      expect(marcas.map(m => m.props('kind'))).toEqual(['to_human', 'to_ai']);
      expect(marcas[1].text()).toBe(
        'A partir daqui, quem responde é o assistente virtual'
      );
    });

    it('o marcador vem ANTES da mensagem de quem entrou, não depois', () => {
      const wrapper = montarConversa([daIA(1), doHumano(2)]);
      const nos = wrapper.findAll('.ai-handoff-mark, .cm');

      expect(nos[0].classes()).toContain('cm');
      expect(nos[1].classes()).toContain('ai-handoff-mark');
      expect(nos[2].attributes('data-id')).toBe('2');
    });

    it('o marcador é anunciado como status, não como alerta', () => {
      // `alert` interrompe o leitor de tela no meio da frase; troca de atendente
      // é informação, não emergência.
      const wrapper = montarConversa([daIA(1), doHumano(2)]);
      expect(wrapper.find('.ai-handoff-mark').attributes('role')).toBe(
        'status'
      );
    });
  });

  describe('MARCAÇÃO 2 (header) — quem atende agora, persistente', () => {
    it('IA atendendo mostra o rótulo do assistente', () => {
      const wrapper = montarCabecalho(ATTENDANT.AI);
      expect(wrapper.find('[data-attendant="ai"]').text()).toBe(
        'Você está falando com o assistente virtual'
      );
    });

    it('depois do handoff, o header muda para a equipe', () => {
      const wrapper = montarCabecalho(ATTENDANT.HUMAN);
      expect(wrapper.find('[data-attendant="human"]').text()).toBe(
        'Você está falando com a equipe'
      );
      expect(wrapper.find('[data-attendant="ai"]').exists()).toBe(false);
    });

    it('sem atendente conhecido, o header NÃO inventa rótulo', () => {
      const wrapper = montarCabecalho(ATTENDANT.UNKNOWN);
      expect(wrapper.find('[data-attendant]').exists()).toBe(false);
    });

    it('a cor do rótulo sai de --w-on-brand, nunca cravada', async () => {
      // O cabeçalho é pintado com a cor da marca; branco cravado deixaria o
      // rótulo ilegível em toda inbox de marca clara.
      //
      // Leitura INCONDICIONAL do arquivo: a primeira versão deste teste lia via
      // `ChatHeader.__file` e só asseria se ele existisse — asserção que pode
      // pular em silêncio é asserção que não existe.
      const { readFileSync } = await import('node:fs');
      const { join } = await import('node:path');
      const fonte = readFileSync(
        join(process.cwd(), 'app/javascript/widget/components/ChatHeader.vue'),
        'utf8'
      );

      expect(fonte).toContain('var(--w-on-brand');
      // E o rótulo não pode voltar a ser branco cravado.
      expect(fonte).not.toMatch(
        /\.chat-header__atendente[\s\S]*?color:\s*#fff/i
      );
    });

    it('o rótulo acompanha a conversa de ponta a ponta', () => {
      expect(currentAttendant([daIA(1)])).toBe(ATTENDANT.AI);
      expect(currentAttendant([daIA(1), doHumano(2)])).toBe(ATTENDANT.HUMAN);
      expect(currentAttendant([daIA(1), doHumano(2), daIA(3)])).toBe(
        ATTENDANT.AI
      );
    });
  });

  describe('MARCAÇÃO 3 (bolha) — o rótulo colado na mensagem', () => {
    it('cada bolha carrega o atendente que a escreveu', () => {
      const wrapper = montarConversa([daIA(1), doHumano(2), daIA(3)]);
      const bolhas = wrapper.findAll('.cm');

      expect(bolhas.map(b => b.attributes('data-attendant'))).toEqual([
        'ai',
        'human',
        'ai',
      ]);
    });

    it('a bolha ANTIGA continua dizendo quem a escreveu depois do handoff', () => {
      // Herdar o atendente atual faria a conversa inteira parecer ter vindo de
      // quem atende agora, quando o visitante rola para trás.
      const wrapper = montarConversa([daIA(1), doHumano(2)]);
      expect(wrapper.find('[data-id="1"]').attributes('data-attendant')).toBe(
        'ai'
      );
    });

    it('a mensagem do visitante não ganha rótulo de atendente', () => {
      const wrapper = montarConversa([doVisitante(1), daIA(2)]);
      expect(wrapper.find('[data-id="1"]').attributes('data-attendant')).toBe(
        'unknown'
      );
    });
  });

  describe('aria-busy no streaming', () => {
    it('sem alguém digitando, aria-busy é false — não é ausência', () => {
      // Atributo ausente e `false` não são a mesma coisa para leitor de tela:
      // o primeiro é indefinido, o segundo afirma que a região está estável.
      const wrapper = montarConversa([daIA(1)]);
      expect(wrapper.find('[role="log"]').attributes('aria-busy')).toBe(
        'false'
      );
    });

    it('com alguém digitando, a região é anunciada como ocupada', () => {
      const wrapper = montarConversa([daIA(1)], { isAgentTyping: true });
      expect(wrapper.find('[role="log"]').attributes('aria-busy')).toBe('true');
    });
  });

  describe('i18n — as 9 chaves nas duas línguas, sem emoji', () => {
    it('paridade pt_BR × en', () => {
      expect(Object.keys(ptBR.AI_IDENTITY).sort()).toEqual(
        Object.keys(en.AI_IDENTITY).sort()
      );
      expect(Object.keys(ptBR.AI_IDENTITY)).toHaveLength(9);
    });

    it('nenhum rótulo carrega emoji — nome acessível não leva símbolo', () => {
      const emoji = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]/u;
      Object.values(ptBR.AI_IDENTITY).forEach(texto => {
        expect(emoji.test(texto)).toBe(false);
      });
      Object.values(en.AI_IDENTITY).forEach(texto => {
        expect(emoji.test(texto)).toBe(false);
      });
    });
  });
});
