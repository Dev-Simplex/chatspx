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

/**
 * Monta a conversa com a BOLHA DE VERDADE.
 *
 * `ChatMessage` NAO e stubado: a cadeia real
 * `ConversationWrap -> ChatMessage -> AgentMessage -> MessageRow` monta inteira,
 * e e o `MessageRow` quem decide o rotulo da bolha, lendo `message.sender.type`
 * pelo `attendantOf`. So as FOLHAS sao dubles (balao, avatar, icone), porque
 * nenhuma delas participa da decisao que este arquivo mede.
 *
 * Por que isso importa: a versao anterior deste helper stubava `ChatMessage` por
 * um template que imprimia `message.attendant` — campo que `annotateHandoffs`
 * escreve mas que a bolha real NUNCA le. O bloco "MARCACAO 3" media o proprio
 * duble. Medido: apagando o `<div data-ai-label>` de `MessageRow.vue` a suite
 * inteira continuava 41/41 verde.
 */
const montarConversa = (grupos, { isAgentTyping = false, canal = {} } = {}) => {
  const blocos = Array.isArray(grupos[0]?.messages)
    ? grupos
    : [{ date: 'hoje', messages: grupos }];
  const todas = blocos.flatMap(bloco => bloco.messages);

  window.chatwootWebChannel = {
    enabledFeatures: [],
    avatarUrl: '',
    preChatFormOptions: {},
    ...canal,
  };

  const store = createStore({
    modules: {
      conversation: {
        namespaced: true,
        getters: {
          getEarliestMessage: () => ({}),
          getLastMessage: () => todas[todas.length - 1] || {},
          getAllMessagesLoaded: () => true,
          getIsFetchingList: () => false,
          getConversationSize: () => todas.length,
          getIsAgentTyping: () => isAgentTyping,
          // `ChatMessage` real le este getter para resolver a citacao.
          getConversation: () => ({}),
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
    props: { groupedMessages: blocos },
    global: {
      plugins: [store, i18n],
      stubs: {
        // `WDateSeparator` e nao `DateSeparator`: o bloco 2.04 trocou o
        // separador compartilhado por um primitivo do widget (a pilula). Com o
        // nome antigo o stub nao pega, o componente real monta e `formatDate`
        // estoura com "Invalid time value" na data simbolica `'hoje'` deste
        // arquivo — que nao e data e nao precisa ser, porque o separador nao e
        // o objeto deste teste.
        WDateSeparator: true,
        Spinner: true,
        AgentTypingBubble: true,
        // Folhas. Nenhuma decide rotulo nem marcacao.
        AgentMessageBubble: true,
        UserMessageBubble: true,
        MessageReplyButton: true,
        ReplyToChip: true,
        FluentIcon: true,
        Avatar: true,
        DragWrapper: { template: '<div><slot /></div>' },
      },
      directives: { 'dompurify-html': {} },
    },
  });
};

/** O no da bolha de `id`, na arvore real. */
const bolha = (wrapper, id) => wrapper.find(`#cwmsg-${id}`);

/** O rotulo de IA colado naquela bolha — ou `null` se ela nao tem. */
const rotuloDaBolha = (wrapper, id) => {
  const no = bolha(wrapper, id);
  if (!no.exists()) return null;
  const rotulo = no.find('[data-ai-label]');
  return rotulo.exists() ? rotulo.text() : null;
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
      const nos = wrapper.findAll('.ai-handoff-mark, [id^="cwmsg-"]');

      expect(nos[0].attributes('id')).toBe('cwmsg-1');
      expect(nos[1].classes()).toContain('ai-handoff-mark');
      expect(nos[2].attributes('id')).toBe('cwmsg-2');
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
    // A bolha é montada de verdade: quem imprime o rótulo é `MessageRow.vue`,
    // e o que se lê aqui é o texto que o visitante lê.
    it('a bolha da IA carrega o rótulo, com o texto que vai à tela', () => {
      const wrapper = montarConversa([daIA(1)]);
      expect(rotuloDaBolha(wrapper, 1)).toBe('Assistente virtual');
    });

    it('a bolha do humano NÃO carrega rótulo de IA', () => {
      const wrapper = montarConversa([doHumano(1)]);
      expect(bolha(wrapper, 1).exists()).toBe(true);
      expect(rotuloDaBolha(wrapper, 1)).toBeNull();
    });

    it('a mensagem do visitante não ganha rótulo de atendente', () => {
      const wrapper = montarConversa([doVisitante(1), daIA(2)]);
      expect(bolha(wrapper, 1).exists()).toBe(true);
      expect(rotuloDaBolha(wrapper, 1)).toBeNull();
    });

    it('a bolha ANTIGA continua dizendo quem a escreveu depois do handoff', () => {
      // Herdar o atendente atual faria a conversa inteira parecer ter vindo de
      // quem atende agora, quando o visitante rola para trás.
      const wrapper = montarConversa([daIA(1), doHumano(2), daIA(3)]);

      expect(rotuloDaBolha(wrapper, 1)).toBe('Assistente virtual');
      expect(rotuloDaBolha(wrapper, 2)).toBeNull();
      expect(rotuloDaBolha(wrapper, 3)).toBe('Assistente virtual');
    });

    it('a flag `aiLabelPersistent: false` apaga o rótulo da bolha', () => {
      // A flag da §B.3 tem de chegar até AQUI. Sem esta asserção, ela poderia
      // estar resolvida no `configMixin` e ignorada pela bolha, que é
      // exatamente o defeito que este arquivo existe para não repetir.
      const wrapper = montarConversa([daIA(1)], {
        canal: { profileConfig: { aiLabelPersistent: false } },
      });

      expect(bolha(wrapper, 1).exists()).toBe(true);
      expect(rotuloDaBolha(wrapper, 1)).toBeNull();
    });
  });

  describe('HANDOFF ATRAVESSA O DIA — a conversa é uma só', () => {
    /**
     * O caso real: o bot atende a noite e a equipe responde na manha seguinte.
     * A lista chega ao widget partida em BLOCOS DE DATA (é assim que o
     * separador de dia funciona, bloco 2.02/2.03), e a anotação de handoff
     * rodava POR BLOCO — cada bloco começava com "atendente anterior
     * desconhecido", e `handoffMarkFor` devolve `null` nesse caso, de
     * propósito: a primeira fala da conversa não é transferência de ninguém.
     *
     * O efeito é que a PRIMEIRA fala de atendente de cada dia nunca gerava
     * marcador. A troca mais visível do produto — bot à noite, gente de manhã —
     * era exatamente a que passava calada.
     *
     * Handoff é uma TRANSIÇÃO, e a transição não é do bloco de data: é da
     * conversa. Por isso a anotação passa a rodar sobre a lista inteira, em
     * ordem, e só depois volta a ser fatiada nos blocos que o separador desenha.
     */
    const ontemBotHojeEquipe = [
      { date: 'ontem', messages: [daIA(1), doVisitante(2)] },
      { date: 'hoje', messages: [doHumano(3)] },
    ];

    it('bot à noite, equipe de manhã: o marcador aparece no dia seguinte', () => {
      const wrapper = montarConversa(ontemBotHojeEquipe);
      const marcas = wrapper.findAllComponents(AiHandoffMark);

      expect(marcas).toHaveLength(1);
      expect(marcas[0].props('kind')).toBe('to_human');
      expect(marcas[0].text()).toBe('A partir daqui, quem responde é a equipe');
    });

    it('o marcador nasce no bloco do dia NOVO, colado na fala que entrou', () => {
      const wrapper = montarConversa(ontemBotHojeEquipe);
      const blocos = wrapper.findAll('.messages-wrap');

      expect(blocos).toHaveLength(2);
      // Ontem só teve o assistente: ninguém foi transferido lá.
      expect(blocos[0].find('.ai-handoff-mark').exists()).toBe(false);
      expect(blocos[1].find('.ai-handoff-mark').exists()).toBe(true);
    });

    it('a VOLTA à IA também atravessa o dia', () => {
      const wrapper = montarConversa([
        { date: 'ontem', messages: [doHumano(1)] },
        { date: 'hoje', messages: [daIA(2)] },
      ]);
      const marcas = wrapper.findAllComponents(AiHandoffMark);

      expect(marcas).toHaveLength(1);
      expect(marcas[0].props('kind')).toBe('to_ai');
    });

    it('mesmo atendente nos dois dias NÃO inventa marcador', () => {
      // O contrapeso: se atravessar o dia passasse a marcar qualquer virada de
      // bloco, todo dia de conversa ganharia um aviso que não informa nada.
      const wrapper = montarConversa([
        { date: 'ontem', messages: [daIA(1)] },
        { date: 'hoje', messages: [daIA(2)] },
      ]);

      expect(wrapper.findAllComponents(AiHandoffMark)).toHaveLength(0);
    });

    it('a bolha de cada dia guarda o próprio atendente', () => {
      const wrapper = montarConversa(ontemBotHojeEquipe);

      expect(rotuloDaBolha(wrapper, 1)).toBe('Assistente virtual');
      expect(rotuloDaBolha(wrapper, 3)).toBeNull();
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

    /**
     * AS CHAVES DECLARADAS QUE NINGUEM APLICA — decisao ABERTA, escalada.
     *
     * Quatro das nove chaves de `AI_IDENTITY` existem nos dois idiomas e nao
     * sao lidas por nenhuma linha de producao. A mais visivel e `HUMAN_LABEL`:
     * no sentido IA -> humano so DUAS das tres marcacoes aparecem, porque a
     * bolha do atendente humano nao recebe rotulo nenhum.
     *
     * ESTE TESTE NAO DECIDE NADA. Ele PRENDE o fato, que ate agora era
     * invisivel: nao havia como saber, sem varrer o repositorio a mao, que a
     * chave estava morta. A decisao — aplicar `HUMAN_LABEL` (e as outras tres)
     * ou remove-las e corrigir o aceite — nao esta na §12 do PLANO-MESTRE, que
     * nao menciona `HUMAN_LABEL` em nenhuma linha. Escalada no relatorio.
     *
     * Quando a decisao vier, este teste REPROVA — e e para reprovar: quem
     * aplicar uma chave tem de mover o nome de uma lista para a outra, o que
     * torna a mudanca deliberada em vez de silenciosa.
     */
    it('as 4 chaves sem consumidor continuam sendo exatamente estas 4', async () => {
      const { readdirSync, readFileSync, statSync } = await import('node:fs');
      const { join } = await import('node:path');

      const RAIZ = 'app/javascript/widget';
      const varrer = dir =>
        readdirSync(dir).flatMap(nome => {
          const caminho = join(dir, nome);
          if (statSync(caminho).isDirectory()) {
            // `specs/` fica de fora: um teste citando a chave nao e um
            // consumidor — foi assim que a chave morta passou por viva.
            return nome === 'specs' || nome === 'i18n' ? [] : varrer(caminho);
          }
          return /\.(vue|js)$/.test(nome) ? [caminho] : [];
        });

      const usadas = new Set();
      varrer(RAIZ).forEach(caminho => {
        const fonte = readFileSync(caminho, 'utf8');
        [...fonte.matchAll(/AI_IDENTITY\.([A-Z_]+)/g)].forEach(m =>
          usadas.add(m[1])
        );
      });

      const declaradas = Object.keys(ptBR.AI_IDENTITY);
      const semConsumidor = declaradas.filter(k => !usadas.has(k)).sort();

      expect([...usadas].sort()).toEqual([
        'AI_LABEL',
        'HANDOFF_TO_AI',
        'HANDOFF_TO_HUMAN',
        'HEADER_AI',
        'HEADER_HUMAN',
      ]);
      expect(semConsumidor).toEqual([
        'BUBBLE_FROM_AI',
        'BUBBLE_FROM_HUMAN',
        'HUMAN_LABEL',
        'STREAMING',
      ]);
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
