/**
 * MECANISMO DE ACEITE DO BLOCO 3.17.
 *
 * Aceite do PLANO-MESTRE §2.2 / 22-plano-widget §C.13:
 *   "Com `showKnowledgeBase: false`, **nenhum request a `/articles` sai**"
 *
 * O plano é explícito em `22-plano-widget:1255` — "não é só esconder o bloco". Por isso o
 * espião vai na camada que EMITE a requisição (`widget/helpers/axios` → `API.get`), e não
 * no dispatch do Vuex: esconder o componente e continuar buscando passaria num teste de
 * dispatch e falharia na aba de rede do cliente.
 *
 * O caminho exercitado é o real e inteiro:
 *   Home.vue → ArticleContainer.vue (onMounted) → store article/fetch → api/article → API.get
 */
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { API } from 'widget/helpers/axios';
import articles from 'widget/store/modules/articles';
import appConfig from 'widget/store/modules/appConfig';
import HomeView from '../Home.vue';

vi.mock('widget/helpers/axios', () => ({
  API: { get: vi.fn(() => Promise.resolve({ data: { payload: [] } })) },
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ locale: { value: 'pt_BR' } }),
}));

vi.mock('shared/helpers/cache', () => ({
  getFromCache: vi.fn(() => null),
  setCache: vi.fn(),
}));

const PORTAL = {
  slug: 'ajuda',
  config: { allowed_locales: ['pt_BR', 'en'] },
};

const buildStore = () =>
  createStore({
    modules: {
      article: { namespaced: true, ...articles },
      appConfig,
      agent: {
        namespaced: true,
        getters: { availableAgents: () => [] },
      },
      conversation: {
        namespaced: true,
        getters: {
          getConversationSize: () => 0,
          getUnreadMessageCount: () => 0,
        },
      },
    },
  });

const mountHome = () =>
  mount(HomeView, {
    global: {
      plugins: [buildStore()],
      mocks: { $t: key => key },
      stubs: { TeamAvailability: true },
    },
  });

/** Toda URL que o widget pediu nesta montagem. */
const requestedUrls = () => API.get.mock.calls.map(([url]) => url);

describe('3.17 — base de conhecimento governada por flag', () => {
  beforeEach(() => {
    API.get.mockClear();
    window.chatwootWebChannel = { portal: PORTAL };
  });

  afterEach(() => {
    delete window.chatwootWebChannel;
  });

  describe('showKnowledgeBase: false', () => {
    beforeEach(() => {
      window.chatwootWebChannel = {
        portal: PORTAL,
        profileConfig: { showKnowledgeBase: false },
      };
    });

    it('NENHUM request a /articles sai — o aceite literal do bloco', async () => {
      mountHome();
      await flushPromises();

      expect(requestedUrls().filter(url => url.includes('articles'))).toEqual(
        []
      );
    });

    it('nem request nenhum, aliás: o container não chega a montar', async () => {
      const wrapper = mountHome();
      await flushPromises();

      expect(API.get).not.toHaveBeenCalled();
      expect(wrapper.findComponent({ name: 'ArticleContainer' }).exists()).toBe(
        false
      );
    });

    it('e continua valendo no perfil marketing inteiro da §B.4', async () => {
      window.chatwootWebChannel = {
        portal: PORTAL,
        profileConfig: {
          showKnowledgeBase: false,
          showConversationList: false,
          homeLayout: 'marketing',
          captureFlow: 'conversational',
          primaryExit: 'whatsapp',
        },
      };

      mountHome();
      await flushPromises();

      expect(requestedUrls().filter(url => url.includes('articles'))).toEqual(
        []
      );
    });
  });

  describe('showKnowledgeBase: true (o default, e o comportamento de hoje)', () => {
    it('o request a /articles sai, com o slug e o locale do portal', async () => {
      mountHome();
      await flushPromises();

      expect(requestedUrls()).toContain('/hc/ajuda/pt_BR/articles.json');
    });

    it('a flag ausente NÃO desliga a base — degradação preserva o hoje', async () => {
      window.chatwootWebChannel = { portal: PORTAL };

      mountHome();
      await flushPromises();

      expect(requestedUrls()).toContain('/hc/ajuda/pt_BR/articles.json');
    });
  });

  describe('homeLayout — a tela inicial por perfil', () => {
    it('sem profileConfig a home é `support`, e é o comportamento de hoje', async () => {
      const wrapper = mountHome();
      await flushPromises();

      expect(wrapper.attributes('data-home-layout')).toBe('support');
      expect(wrapper.findComponent({ name: 'ArticleContainer' }).exists()).toBe(
        true
      );
    });

    it('`marketing` marca a home e some com o bloco de artigos (§B.4)', async () => {
      window.chatwootWebChannel = {
        portal: PORTAL,
        profileConfig: { homeLayout: 'marketing', showKnowledgeBase: false },
      };

      const wrapper = mountHome();
      await flushPromises();

      expect(wrapper.attributes('data-home-layout')).toBe('marketing');
      expect(wrapper.findComponent({ name: 'ArticleContainer' }).exists()).toBe(
        false
      );
    });

    it('R5 — a home `support` não ganhou nem perdeu nó: os 16 snapshots seguem válidos', async () => {
      const wrapper = mountHome();
      await flushPromises();

      // O bloco 3.17 acrescentou APENAS um atributo `data-*` (inerte no render) e um
      // `v-if` que, no default, resolve para `true`. Nenhum elemento entrou ou saiu na
      // inbox sem `widget_profile` gravado — que é o que a regra R5 / o aceite de W3.1
      // protege com os 16 snapshots de regressão visual.
      expect(wrapper.findComponent({ name: 'ArticleContainer' }).exists()).toBe(
        true
      );
      expect(wrapper.find('[data-home-layout]').classes()).toEqual([
        'z-50',
        'flex',
        'flex-col',
        'justify-end',
        'flex-1',
        'w-full',
        'p-4',
        'gap-4',
      ]);
    });
  });

  describe('sem portal configurado', () => {
    it('não sai request nem com a flag ligada — não há o que buscar', async () => {
      window.chatwootWebChannel = {
        profileConfig: { showKnowledgeBase: true },
      };

      mountHome();
      await flushPromises();

      expect(API.get).not.toHaveBeenCalled();
    });
  });
});
