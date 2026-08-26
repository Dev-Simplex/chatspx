/**
 * Mecanismo de aceite do bloco 2.02 — `MessageRow` unifica as duas linhas.
 *
 * ACEITE (§2.2): «`AgentMessage`+`UserMessage` < 150 linhas somados; nenhum
 * seletor de irmão adjacente para agrupar».
 *
 * As duas metades são medidas por arquivo, não por leitura: a primeira conta as
 * linhas dos dois componentes, a segunda varre a folha da conversa atrás de
 * `+`/`~` entre as classes de linha. Um comentário citando o seletor antigo não
 * pode reprovar — por isso a varredura tira comentário antes de olhar.
 *
 * O resto do arquivo mede o que a unificação NÃO podia mudar: as duas variantes
 * continuam desenhando a marcação que os 20 snapshots do widget cobrem.
 */
import { readFileSync } from 'node:fs';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import MessageRow from '../MessageRow.vue';

const TETO_DE_LINHAS = 150;
const CASCAS = [
  'app/javascript/widget/components/AgentMessage.vue',
  'app/javascript/widget/components/UserMessage.vue',
];

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

const montar = props =>
  mount(MessageRow, {
    props,
    global: {
      plugins: [i18n],
      mocks: { $t: chave => i18n.global.t(chave) },
      stubs: {
        Avatar: true,
        AgentMessageBubble: true,
        UserMessageBubble: true,
        MessageReplyButton: true,
        ReplyToChip: true,
        FluentIcon: true,
        DragWrapper: { template: '<div><slot /></div>' },
      },
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

describe('2.02 — o teto de linhas das duas cascas', () => {
  it(`AgentMessage + UserMessage somam menos de ${TETO_DE_LINHAS} linhas`, () => {
    const porArquivo = CASCAS.map(caminho => [
      caminho,
      readFileSync(caminho, 'utf8').split('\n').length,
    ]);
    const soma = porArquivo.reduce((total, [, linhas]) => total + linhas, 0);

    // A mensagem do erro traz a conta, porque quem reprovar aqui precisa saber
    // qual dos dois cresceu.
    expect({ porArquivo, soma }).toEqual({
      porArquivo,
      soma: expect.any(Number),
    });
    expect(soma).toBeLessThan(TETO_DE_LINHAS);
  });

  it('nenhum seletor de irmão adjacente decide agrupamento', () => {
    const folha = readFileSync(
      'app/javascript/widget/assets/scss/views/_conversation.scss',
      'utf8'
    )
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/^\s*\/\/.*$/gm, '');

    const irmaos = [
      ...folha.matchAll(/\.[\w-]*message[\w-]*\s*[+~]\s*\./g),
    ].map(m => m[0]);

    expect(irmaos).toEqual([]);
  });
});

describe('2.02 — a linha unificada desenha as duas variantes', () => {
  it('variante do agente: o invólucro, o avatar e o nome', () => {
    const w = montar({
      variant: 'agent',
      message: {
        id: 1,
        content: 'Olá',
        message_type: 1,
        showAvatar: true,
        sender: { name: 'Marina', avatar_url: '/a.png' },
      },
    });

    expect(w.find('.agent-message-wrap').exists()).toBe(true);
    expect(w.find('.user-message-wrap').exists()).toBe(false);
    expect(w.find('avatar-stub').exists()).toBe(true);
    expect(w.find('avatar-stub').attributes('name')).toBe('Marina');
    // O nome sai por `v-dompurify-html`, e a diretiva aqui é um dublê — por
    // isso a asserção é sobre o nó existir, não sobre o texto dentro dele.
    expect(w.find('.agent-name').exists()).toBe(true);
  });

  it('variante do visitante: o invólucro e o balão, sem avatar', () => {
    const w = montar({
      variant: 'user',
      message: { id: 2, content: 'Oi', message_type: 0, status: 'sent' },
    });

    expect(w.find('.user-message-wrap').exists()).toBe(true);
    expect(w.find('.agent-message-wrap').exists()).toBe(false);
    expect(w.find('avatar-stub').exists()).toBe(false);
    expect(w.find('user-message-bubble-stub').exists()).toBe(true);
  });

  it('mensagem falhada do visitante: o botão de reenvio aparece', () => {
    const w = montar({
      variant: 'user',
      message: { id: 3, content: 'Oi', message_type: 0, status: 'failed' },
    });

    expect(w.find('.message-wrap').classes()).toContain('is-failed');
    expect(w.find('button').attributes('title')).toBe(
      ptBR.COMPONENTS.MESSAGE_BUBBLE.RETRY
    );
  });

  it('em progresso: sem botão de responder e com a classe de opacidade', () => {
    const w = montar({
      variant: 'user',
      message: { id: 4, content: 'Oi', message_type: 0, status: 'in_progress' },
    });

    expect(w.find('.message-wrap').classes()).toContain('in-progress');
    expect(w.find('message-reply-button-stub').exists()).toBe(false);
  });

  it('a resposta gravada do visitante é uma linha de VISITANTE dentro da linha do agente', () => {
    const w = montar({
      variant: 'agent',
      message: {
        id: 5,
        content: 'Escolha:',
        message_type: 3,
        content_type: 'input_select',
        content_attributes: {
          submitted_values: [{ title: 'Sim', value: 'yes' }],
        },
      },
    });

    const externo = w.find('.agent-message-wrap');
    expect(externo.exists()).toBe(true);
    // Aninhada, não irmã: era isto que o `.has-response + .user-message-wrap`
    // dependia de acertar sozinho no CSS.
    expect(externo.find('.user-message-wrap').exists()).toBe(true);
  });

  it('o carimbo de hora do agente traz a data; o do visitante, só a hora', () => {
    const anexo = [
      { id: 9, file_type: 'file', data_url: 'https://exemplo/x.pdf' },
    ];
    // `messageStamp` recebe UNIX epoch em segundos (`fromUnixTime`), não ISO.
    const criado = 1736942400;

    const agente = montar({
      variant: 'agent',
      message: { id: 6, content: 'a', created_at: criado, attachments: anexo },
    });
    const visitante = montar({
      variant: 'user',
      message: { id: 7, content: 'a', created_at: criado, attachments: anexo },
    });

    const doAgente = agente.find('.message-time').text();
    const doVisitante = visitante.find('.message-time').text();
    expect(doAgente).not.toBe(doVisitante);
    expect(doAgente.length).toBeGreaterThan(doVisitante.length);
  });
});
