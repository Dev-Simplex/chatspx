import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import conversationEn from 'dashboard/i18n/locale/en/conversation.json';
import ContactPanel from '../ContactPanel.vue';

/**
 * Bloco 5.23 — **a seção que não aparece quando não tem o que dizer.**
 *
 * ── POR QUE ESTE ARQUIVO EXISTE, JÁ HAVENDO `contact/specs/SiteContext.spec.js` ─────────
 *
 * O spec vizinho monta o `SiteContext` sozinho e prova que, sem nada do site, ele não
 * renderiza. Isso é verdade e não bastava: o `v-if` mora DENTRO do componente, e quem desenha
 * o título é o `AccordionItem` que o envolve, no `ContactPanel`. O `AccordionItem` escreve o
 * cabeçalho a partir da prop `title`, sem olhar o slot — então "o filho não renderiza" e "a
 * seção some" são duas afirmações diferentes, e só a primeira estava medida.
 *
 * O resultado no navegador: toda conversa de WhatsApp, e-mail ou API — que nunca teve um site
 * mandando UTM nenhuma — ganhava um acordeão permanente escrito "Recebido do site" que abria
 * vazio. Seção vazia é pior que seção ausente: ocupa espaço prometendo dado.
 *
 * Por isso aqui o sujeito da medição é o **wrapper**: o `ContactPanel` de verdade, com o
 * `AccordionItem` de verdade e o `SiteContext` de verdade. Um stub de qualquer um dos três
 * apagaria justamente o defeito, porque o defeito está na junta entre eles.
 *
 * O título vem do arquivo de tradução, não de uma string digitada aqui: renomear a seção não
 * pode deixar este teste verde por acidente.
 */
const TITULO_DA_SECAO =
  conversationEn.CONVERSATION_SIDEBAR.ACCORDION.SITE_CONTEXT;

const CONTACT_ID = 7;
const CONVERSATION_ID = 42;

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
}));

// A forma do `_custom_attribute_definition.json.jbuilder`.
const definicao = (key, model) => ({
  id: key,
  attribute_key: key,
  attribute_display_name: key,
  attribute_display_type: 'text',
  attribute_model: model,
});

const DEFINICOES = [
  definicao('first_utm_campaign', 'contact_attribute'),
  definicao('last_page_path', 'conversation_attribute'),
];

const montarStore = ({
  contactCustomAttributes = {},
  conversationCustomAttributes = {},
  identifier = null,
} = {}) =>
  createStore({
    getters: {
      // A store de CONVERSAS não passa por `camelcaseKeys`: a conversa entra crua, como o
      // servidor a escreve. É a forma que o painel realmente recebe.
      getSelectedChat: () => ({
        id: CONVERSATION_ID,
        custom_attributes: conversationCustomAttributes,
        meta: {
          channel: 'Channel::Whatsapp',
          sender: { id: CONTACT_ID, identifier },
        },
      }),
      // A seção entra ABERTA de propósito: `isContactSidebarItemOpen` é `!!uiSettings[key]`,
      // e o `AccordionItem` só renderiza o slot quando aberto. Fechada, o corpo nunca desce e
      // o teste mediria apenas títulos — inclusive o "vazio", que é exatamente o caso do
      // agente que ABRE a seção e não encontra nada.
      getUISettings: () => ({ is_site_context_open: true }),
    },
    actions: { updateUISettings: vi.fn() },
    modules: {
      contacts: {
        namespaced: true,
        getters: {
          // A store de CONTATOS cameliza a chave do topo (`customAttributes`) e o `stopPaths`
          // preserva o conteúdo em snake_case — medido em
          // `contact/specs/siteContextStoreShape.spec.js`.
          getContact: () => () => ({
            id: CONTACT_ID,
            customAttributes: contactCustomAttributes,
          }),
        },
        actions: { show: vi.fn() },
      },
      attributes: {
        namespaced: true,
        getters: {
          getAttributesByModel: () => model =>
            DEFINICOES.filter(d => d.attribute_model === model),
        },
        actions: { get: vi.fn() },
      },
      macros: {
        namespaced: true,
        getters: { getMacros: () => [] },
        actions: { get: vi.fn() },
      },
      conversationMetadata: {
        namespaced: true,
        getters: { getConversationMetadata: () => () => ({}) },
      },
      integrations: {
        namespaced: true,
        getters: { getIntegration: () => () => ({}) },
        actions: { get: vi.fn() },
      },
      accounts: {
        namespaced: true,
        getters: {
          getAccount: () => () => ({ id: 1 }),
          isFeatureEnabledonAccount: () => () => false,
        },
      },
      globalConfig: {
        namespaced: true,
        getters: { isOnChatwootCloud: () => false },
      },
    },
  });

// Tudo que é stub aqui é vizinho da seção, não a seção. `AccordionItem` e `SiteContext` ficam
// REAIS de propósito: são os dois lados da junta que este arquivo mede.
const stubs = {
  Draggable: {
    props: ['list'],
    template:
      '<div><template v-for="element in list" :key="element.name"><slot name="item" :element="element" /></template></div>',
  },
  SidebarActionsHeader: true,
  ContactInfo: true,
  ConversationSummary: true,
  ConversationChecklist: true,
  ConversationMedia: true,
  GroupParticipants: true,
  ConversationAction: true,
  ConversationParticipant: true,
  ConversationInfo: true,
  CustomAttributes: true,
  ContactConversations: true,
  ContactNotes: true,
  KanbanStatus: true,
  MacrosList: true,
  SharedFiles: true,
  ShopifyOrdersList: true,
  LinearIssuesList: true,
  LinearSetupCTA: true,
  MessageSequenceWidget: true,
  'woot-feature-toggle': { template: '<div><slot /></div>' },
};

/**
 * O `await nextTick()` NAO e enfeite: `conversationSidebarItems` nasce `[]` e so e preenchido
 * no `onMounted`, entao a primeira renderizacao da barra sai SEM nenhum acordeao. Sem esperar,
 * toda asserção negativa deste arquivo passava no vazio — a lista de titulos vinha com um item
 * so, e "nao contem 'Recebido do site'" era verdade por ausencia de tela, nao por guarda.
 * Foi o teste de contraprova abaixo que expos isso.
 */
const montar = async (estado = {}) => {
  const tela = mount(ContactPanel, {
    props: { conversationId: CONVERSATION_ID, inboxId: 1 },
    global: { plugins: [montarStore(estado)], stubs },
  });
  await nextTick();
  return tela;
};

/** Os cabeçalhos que o agente enxerga na barra — o título de cada acordeão. */
const titulosVisiveis = tela =>
  tela.findAll('button').map(b => b.text().trim());

describe('5.23 — o acordeão "recebido do site" no painel de verdade', () => {
  describe('quando o site não mandou nada (WhatsApp, e-mail, API)', () => {
    it('NÃO desenha o cabeçalho da seção', async () => {
      const tela = await montar();

      expect(titulosVisiveis(tela)).not.toContain(TITULO_DA_SECAO);
      expect(tela.text()).not.toContain(TITULO_DA_SECAO);
    });

    it('não desenha o cabeçalho por causa de valor vazio ou nulo', async () => {
      const tela = await montar({
        contactCustomAttributes: {
          first_utm_campaign: '',
          first_utm_source: null,
        },
        conversationCustomAttributes: { last_page_path: '' },
      });

      expect(titulosVisiveis(tela)).not.toContain(TITULO_DA_SECAO);
    });

    /**
     * A contraprova da asserção negativa acima: um título que ESTÁ na tela é encontrado pelo
     * mesmo caminho. Sem isto, `not.toContain` passaria mesmo se `titulosVisiveis` devolvesse
     * lista vazia por um stub errado — e o teste inteiro mediria nada.
     */
    it('e a medição enxerga os cabeçalhos vizinhos, que continuam lá', async () => {
      const tela = await montar();

      expect(titulosVisiveis(tela)).toContain(
        conversationEn.CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES
      );
    });
  });

  describe('quando o site mandou alguma coisa', () => {
    it('desenha o cabeçalho e o conteúdo por causa de um atributo do CONTATO', async () => {
      const tela = await montar({
        contactCustomAttributes: { first_utm_campaign: 'black-friday' },
      });

      expect(titulosVisiveis(tela)).toContain(TITULO_DA_SECAO);
      expect(tela.find('[data-testid="site-context"]').exists()).toBe(true);
      expect(tela.text()).toContain('black-friday');
    });

    it('desenha o cabeçalho por causa de um atributo da CONVERSA', async () => {
      const tela = await montar({
        conversationCustomAttributes: { last_page_path: '/precos' },
      });

      expect(titulosVisiveis(tela)).toContain(TITULO_DA_SECAO);
      expect(tela.text()).toContain('/precos');
    });

    /**
     * Visitante identificado por `setUser` sem UTM nenhuma: a seção existe por causa da
     * identidade (4.15), e é o caso que uma guarda escrita só sobre atributos deixaria de fora.
     */
    it('desenha o cabeçalho só por causa da identidade', async () => {
      const tela = await montar({ identifier: 'CRM-4711' });

      expect(titulosVisiveis(tela)).toContain(TITULO_DA_SECAO);
      expect(tela.text()).toContain('CRM-4711');
    });

    /**
     * O que o AGENTE digitou não pode fazer a seção do SITE aparecer — é a distinção inteira
     * do bloco, e uma guarda preguiçosa (`Object.keys(...).length`) a apagaria.
     */
    it('atributo do agente NÃO faz a seção aparecer', async () => {
      const tela = await montar({
        contactCustomAttributes: { plano_do_cliente: 'ouro' },
        conversationCustomAttributes: { motivo_do_contato: 'suporte' },
      });

      expect(titulosVisiveis(tela)).not.toContain(TITULO_DA_SECAO);
    });
  });

  /**
   * A INVARIANTE que o defeito quebrou, dita em uma frase: cabeçalho e conteúdo aparecem
   * sempre juntos, nunca um sem o outro.
   *
   * As duas decisões moram em arquivos diferentes — o `v-if` do conteúdo no `SiteContext.vue`,
   * o `v-if` do acordeão no `ContactPanel.vue`. Hoje elas chamam a MESMA função
   * (`hasSiteContext`), e este teste é o que reprova quem separar as duas de novo: uma cópia
   * nova da regra num dos lados só se manifesta como cabeçalho vazio (o defeito original) ou
   * como conteúdo sem cabeçalho (o mesmo defeito ao contrário).
   */
  it('cabeçalho e conteúdo nunca aparecem um sem o outro', async () => {
    const casos = [
      ['nada', {}],
      ['só valores vazios', { contactCustomAttributes: { first_gclid: '' } }],
      ['só atributo do agente', { contactCustomAttributes: { plano: 'ouro' } }],
      [
        'origem do contato',
        { contactCustomAttributes: { first_utm_term: 'x' } },
      ],
      [
        'origem da conversa',
        { conversationCustomAttributes: { last_utm_source: 'google' } },
      ],
      ['só identidade', { identifier: 'CRM-4711' }],
    ];

    const observado = await Promise.all(
      casos.map(async ([nome, estado]) => {
        const tela = await montar(estado);
        return [
          nome,
          titulosVisiveis(tela).includes(TITULO_DA_SECAO),
          tela.find('[data-testid="site-context"]').exists(),
        ];
      })
    );

    // Cada linha é [caso, temCabecalho, temConteudo] — e as duas colunas têm de ser iguais.
    expect(observado.map(([nome, cabecalho]) => [nome, cabecalho])).toEqual(
      observado.map(([nome, , conteudo]) => [nome, conteudo])
    );
    // E a tabela precisa ter os dois valores, senão a igualdade acima seria trivial.
    expect(observado.some(([, cabecalho]) => cabecalho)).toBe(true);
    expect(observado.some(([, cabecalho]) => !cabecalho)).toBe(true);
  });
});
