/**
 * Página mínima do aceite de APARÊNCIA do bloco 6.03 — a citação de fonte.
 *
 * POR QUE ELA EXISTE ALÉM DOS 15 TESTES DE UNIDADE
 *
 * Os specs de `citationList.spec.js` rodam em jsdom, e jsdom não resolve cascata,
 * `!important` nem custom property: ele vê a classe e diz "ok". A citação é desenhada
 * com `color: rgb(var(--slate-11))` sobre o fundo da conversa — três coisas que só
 * existem no navegador. Um `--slate-11` que não resolvesse tornaria a função inteira
 * inválida e o Chromium devolveria o preto herdado, com o teste de unidade verde do
 * mesmo jeito (é a mesma armadilha documentada no verificador do 4.09).
 *
 * O que se monta aqui é o componente REAL dentro da hierarquia REAL da conversa
 * (`.conversation-wrap > .agent-message-wrap > .agent-message`), com o CSS REAL do
 * widget. O rodapé de citação é irmão da bolha, não filho dela — então o fundo que
 * importa é o da CONVERSA, e reproduzir a hierarquia é o que faz a medição medir isso.
 */
import { createApp, h } from 'vue';
import { createI18n } from 'vue-i18n';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import AgentMessageBubble from 'widget/components/AgentMessageBubble.vue';
// O CSS entra pelo shim `widget/wootStyles.harness.scss` — a razão (a base do `@config`
// do Tailwind e os 3.862 módulos que o App.vue arrastava) está no cabeçalho do shim.
import 'widget/wootStyles.harness.scss';

// As duas formas que a citação assume, e as duas são aceite:
//
//   1. COM url pública → vira link. O título traz um emoji DE PROPÓSITO: ele vem do
//      cliente, que põe emoji em nome de documento, e o aceite é que o símbolo fique
//      na tela e saia do nome acessível.
//   2. SEM url (PDF interno) → NÃO vira link. Um link que não abre é pior que nenhum.
const CITACOES = [
  {
    title: '🔥 Política de trocas e devoluções',
    url: 'https://exemplo.test/politica-de-trocas',
    excerpt: 'Trocas em até 30 dias corridos, com nota fiscal.',
  },
  {
    title: 'Manual interno de atendimento',
    url: null,
    excerpt: 'Documento interno, sem URL pública.',
  },
];

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

const app = createApp({
  render() {
    // A hierarquia vem dos templates reais: `Messages.vue` (o fundo da área de chat),
    // `ConversationWrap.vue` e `_conversation.scss`. Nada de fundo inventado aqui — é
    // o que decide a razão de contraste medida abaixo.
    return h(
      'div',
      { class: 'flex flex-col flex-1 bg-n-slate-2 dark:bg-n-solid-1' },
      h(
        'div',
        {
          class:
            'flex flex-col flex-1 overflow-hidden rounded-b-lg bg-n-chat-bg dark:bg-n-solid-1',
        },
        h(
          'div',
          { class: 'conversation-wrap' },
          h(
            'div',
            { class: 'agent-message-wrap' },
            h(
              'div',
              { class: 'agent-message' },
              h(AgentMessageBubble, {
                contentType: 'text',
                messageId: 1,
                message: 'A troca pode ser feita em até 30 dias com a nota.',
                messageContentAttributes: { citations: CITACOES },
              })
            )
          )
        )
      )
    );
  },
});

app.use(i18n);
app.use(VueDOMPurifyHTML);
app.mount('#app');
