/**
 * Mecanismo de aceite do bloco 2.06 — o cabeçalho.
 *
 * ACEITE (§2.2): "Exatamente 1 `h1`; nenhum `text-white`; alvos >= 44x44 em
 * 375 px", mais o que a linha do bloco pede: `<main>`, avatar 32 raio 6, ações
 * 40/44, status com rótulo textual.
 *
 * Este arquivo cobre o que é MARCAÇÃO e TRADUÇÃO — jsdom resolve as duas. O que
 * é GEOMETRIA e COR COMPUTADA (56/96, 44x44, a cor derivada de `--w-on-brand`)
 * mora em `specs/browser/header-geometry.check.mjs`, porque jsdom não resolve
 * cascade, `!important` nem custom property: ali um verde seria afirmação, não
 * medição.
 */
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import ChatHeader from '../ChatHeader.vue';
import ChatHeaderExpanded from '../ChatHeaderExpanded.vue';

const componentDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const source = name => readFileSync(join(componentDir, name), 'utf8');

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

global.chatwootWebChannel = {
  enabledFeatures: [],
  workingHoursEnabled: false,
};

const store = createStore({
  modules: {
    appConfig: {
      namespaced: true,
      getters: {
        getAppConfig: () => ({}),
        getAvailableMessage: () => 'Estamos conectados',
        getUnavailableMessage: () => 'Estamos ausentes no momento',
        getCanUserEndConversation: () => false,
      },
    },
    agent: { namespaced: true, getters: { availableAgents: () => [] } },
    conversationAttributes: {
      namespaced: true,
      getters: { getConversationParams: () => ({ status: 'open' }) },
    },
  },
});

const mountHeader = (component, props = {}) =>
  mount(component, {
    props,
    global: {
      plugins: [store, i18n],
      stubs: {
        HeaderActions: true,
        AvailabilityContainer: true,
        FluentIcon: true,
        RouterLink: true,
      },
      mocks: { $route: { name: 'messages' } },
      directives: {
        dompurifyHtml: (el, binding) => {
          el.innerHTML = binding.value;
        },
      },
    },
  });

describe('2.06 — o cabeçalho tem um título de verdade', () => {
  it('o cabeçalho colapsado traz EXATAMENTE um h1, com o nome do site', () => {
    const wrapper = mountHeader(ChatHeader, { title: 'Simplex Soluções' });

    const h1 = wrapper.findAll('h1');
    expect(h1).toHaveLength(1);
    expect(h1[0].text()).toBe('Simplex Soluções');
  });

  it('o cabeçalho expandido traz EXATAMENTE um h1, com o título de boas-vindas', () => {
    const wrapper = mountHeader(ChatHeaderExpanded, {
      introHeading: 'Olá! Como podemos ajudar?',
      introBody: 'Respondemos em minutos.',
    });

    const h1 = wrapper.findAll('h1');
    expect(h1).toHaveLength(1);
    expect(h1[0].text()).toBe('Olá! Como podemos ajudar?');
  });

  it('nenhum dos dois cabeçalhos traz um segundo título de nível 1', () => {
    // Os dois nunca coexistem (`v-if`/`v-if` em ViewWithHeader), então cada um
    // ter o seu `h1` mantém a promessa "exatamente 1" em QUALQUER tela.
    const colapsado = mountHeader(ChatHeader, { title: 'A' });
    const expandido = mountHeader(ChatHeaderExpanded, { introHeading: 'B' });

    expect(colapsado.findAll('h1, h2, h3')).toHaveLength(1);
    expect(expandido.findAll('h1')).toHaveLength(1);
  });
});

describe('2.06 — o status não é só uma bolinha colorida', () => {
  it('o ponto de disponibilidade tem rótulo textual quando a equipe está online', () => {
    const wrapper = mountHeader(ChatHeader, {
      title: 'Simplex',
      availableAgents: [{ id: 1, availability_status: 'online' }],
    });

    const dot = wrapper.find('[data-testid="availability-dot"]');
    expect(dot.exists()).toBe(true);
    expect(dot.attributes('aria-label')).toBe('Estamos conectados');
    expect(dot.attributes('role')).toBe('img');
  });

  it('e rótulo próprio quando está offline — cor sozinha não informa nada', () => {
    const wrapper = mountHeader(ChatHeader, { title: 'Simplex' });

    const dot = wrapper.find('[data-testid="availability-dot"]');
    expect(dot.exists()).toBe(true);
    expect(dot.attributes('aria-label')).toBe('Estamos ausentes no momento');
  });
});

describe('2.06 — nenhuma cor de texto cravada sobre a marca', () => {
  // `text-white` cravado quebra toda inbox cuja marca é clara: o servidor
  // calcula `--w-on-brand` por luminância, e é ele que decide preto ou branco.
  const arquivos = [
    'ChatHeader.vue',
    'ChatHeaderExpanded.vue',
    'HeaderActions.vue',
    'layouts/ViewWithHeader.vue',
  ];

  it.each(arquivos)('%s não usa text-white nem bg-white', arquivo => {
    const conteudo = source(arquivo);
    const template =
      /<template>([\s\S]*)<\/template>/.exec(conteudo)?.[1] ?? '';

    expect(template).not.toMatch(/\btext-white\b/);
    expect(template).not.toMatch(/\bbg-white\b/);
  });
});

describe('2.06 — a região principal existe', () => {
  it('ViewWithHeader marca o conteúdo com <main>, uma vez só', () => {
    const template =
      /<template>([\s\S]*)<\/template>/.exec(
        source('layouts/ViewWithHeader.vue')
      )?.[1] ?? '';

    expect(template.match(/<main[\s>]/g) ?? []).toHaveLength(1);
    expect(template).toMatch(/<main[^>]*>[\s\S]*<router-view[\s\S]*<\/main>/);
  });
});
