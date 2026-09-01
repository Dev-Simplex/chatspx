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
import AvailabilityContainer from '../Availability/AvailabilityContainer.vue';

const componentDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const source = name => readFileSync(join(componentDir, name), 'utf8');

// `legacy: false` porque é o que `entrypoints/widget.js:20` usa em produção.
// Estava `true` aqui, e a diferença não é cosmética: em modo legado o
// `useI18n()` lança "Not available in legacy mode", então qualquer componente
// do widget que traduza no `<script setup>` — `AvailabilityContainer` já fazia —
// só podia ser medido com dublê. Um spec que roda numa configuração de i18n que
// não vai ao ar mede outra coisa. Com `legacy: false`, `globalInjection` já vem
// ligado (vue-i18n 9.14), e o `$t` dos templates continua valendo.
const i18n = createI18n({
  legacy: false,
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

describe('2.06 — o status tem rótulo TEXTUAL VISÍVEL, não só um nome acessível', () => {
  /**
   * A 6ª entrega da linha do bloco é "status com rótulo textual". A entrega
   * anterior pagou isso com `role="img"` + `aria-label` no ponto: nome
   * acessível é para LEITOR DE TELA. Quem enxerga e não distingue as duas
   * opacidades da MESMA cor (deltaE 7,9 em deuteranopia) continua sem saber se
   * tem alguém do outro lado. `aria-label` não é texto visível, e chamar um de
   * outro é o que fez este bloco passar sem entregar.
   *
   * Por isso a medição aqui é sobre `.text()` — o que sobra depois que toda
   * cor, classe e atributo somem.
   */
  const AGENTE_ONLINE = [{ id: 1, availability_status: 'online' }];

  it('online: a palavra aparece no texto renderizado, não num atributo', () => {
    const wrapper = mountHeader(ChatHeader, {
      title: 'Simplex',
      availableAgents: AGENTE_ONLINE,
    });

    const rotulo = wrapper.find('[data-testid="availability-label"]');
    expect(rotulo.exists()).toBe(true);
    expect(rotulo.text()).toBe('Estamos conectados');
    // E está no texto do cabeçalho INTEIRO: um `sr-only` passaria na asserção
    // acima e continuaria invisível.
    expect(wrapper.text()).toContain('Estamos conectados');
    expect(rotulo.classes()).not.toContain('sr-only');
    expect(rotulo.attributes('aria-hidden')).toBeUndefined();
  });

  it('offline: idem, com a palavra do outro estado', () => {
    const wrapper = mountHeader(ChatHeader, { title: 'Simplex' });

    const rotulo = wrapper.find('[data-testid="availability-label"]');
    expect(rotulo.exists()).toBe(true);
    expect(rotulo.text()).toBe('Estamos ausentes no momento');
    expect(wrapper.text()).toContain('Estamos ausentes no momento');
  });

  /**
   * ESTA é a asserção que a entrega anterior não conseguia passar, e a razão
   * de o bloco existir: apagados TODOS os atributos (classe, style, aria), os
   * dois estados ainda têm de ser distinguíveis. Se a diferença morasse só na
   * opacidade, os dois textos seriam idênticos e o teste cairia.
   */
  it('sem NENHUM atributo, os dois estados continuam distinguíveis', () => {
    const online = mountHeader(ChatHeader, {
      title: 'Simplex',
      availableAgents: AGENTE_ONLINE,
    });
    const offline = mountHeader(ChatHeader, { title: 'Simplex' });

    const semAtributos = wrapper => {
      const el = wrapper.element.cloneNode(true);
      el.querySelectorAll('*').forEach(no => {
        while (no.attributes.length) no.removeAttribute(no.attributes[0].name);
      });
      return el.textContent.replace(/\s+/g, ' ').trim();
    };

    const textoOnline = semAtributos(online);
    const textoOffline = semAtributos(offline);

    expect(textoOnline).not.toBe(textoOffline);
    expect(textoOnline).toContain('Estamos conectados');
    expect(textoOffline).toContain('Estamos ausentes no momento');
  });

  it('o ponto virou decoração: não repete o status para o leitor de tela', () => {
    const wrapper = mountHeader(ChatHeader, {
      title: 'Simplex',
      availableAgents: AGENTE_ONLINE,
    });

    const dot = wrapper.find('[data-testid="availability-dot"]');
    expect(dot.exists()).toBe(true);
    // Agora quem carrega o significado é o texto ao lado. Manter `role="img"` +
    // `aria-label` aqui faria o leitor de tela anunciar o estado DUAS vezes.
    expect(dot.attributes('aria-hidden')).toBe('true');
    expect(dot.attributes('aria-label')).toBeUndefined();
    expect(dot.attributes('role')).toBeUndefined();
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

/**
 * Por que o `:show-header="false"` do `AvailabilityContainer` CONTINUA falso.
 *
 * A leitura óbvia de "falta rótulo textual" é ligar o cabeçalho do
 * `AvailabilityContainer` e pronto. Isso importaria um SEGUNDO estado, calculado
 * por um predicado DIFERENTE do que pinta o ponto:
 *
 *   ponto  → `isOnline`    = dentro do horário E com agente conectado
 *   texto  → `isAvailable` = `isOnline` OU (horário habilitado E dentro dele)
 *
 * Existe estado alcançável em que os dois discordam — horário comercial
 * habilitado, aberto agora, e NENHUM agente conectado — e é justamente o estado
 * em que o ponto diz "ausente" e o texto ao lado diria "conectados". O rótulo
 * mora no próprio `ChatHeader`, lendo a MESMA fonte do ponto; o cabeçalho do
 * container fica desligado. Este bloco existe para que a divergência seja
 * MEDIDA, e não uma afirmação de comentário: se um dia os dois predicados
 * convergirem, ele cai e o `show-header` pode ser reavaliado.
 */
describe('2.06 — ponto e rótulo saem da MESMA fonte', () => {
  // Forma REAL do payload: `show.html.erb:59` serializa `inbox.working_hours`
  // com `to_json`, ou seja, chaves snake_case do ActiveRecord.
  const HORARIO_ABERTO_TODO_DIA = Array.from({ length: 7 }, (_, dia) => ({
    day_of_week: dia,
    open_all_day: true,
    closed_all_day: false,
  }));

  const comHorarioComercial = () => {
    global.chatwootWebChannel = {
      enabledFeatures: [],
      workingHoursEnabled: true,
      workingHours: HORARIO_ABERTO_TODO_DIA,
      timezone: 'UTC',
      utcOffset: 'UTC',
    };
  };

  afterEach(() => {
    global.chatwootWebChannel = {
      enabledFeatures: [],
      workingHoursEnabled: false,
    };
  });

  it('aberto agora e sem agente: ponto e rótulo dizem a MESMA coisa', () => {
    comHorarioComercial();

    const wrapper = mountHeader(ChatHeader, {
      title: 'Simplex',
      availableAgents: [],
    });

    const rotulo = wrapper.find('[data-testid="availability-label"]');
    const dot = wrapper.find('[data-testid="availability-dot"]');

    // Ninguém do outro lado: os DOIS têm de dizer ausente.
    expect(rotulo.text()).toBe('Estamos ausentes no momento');
    expect(dot.classes()).toContain('opacity-40');
    expect(dot.classes()).not.toContain('opacity-80');
  });

  it('e o cabeçalho do AvailabilityContainer diria o CONTRÁRIO nesse estado', () => {
    comHorarioComercial();

    const container = mount(AvailabilityContainer, {
      props: { agents: [], showHeader: true, showAvatars: false },
      global: { plugins: [store, i18n] },
    });

    // Prova viva de que ligar o `show-header` colocaria dois estados brigando
    // lado a lado no mesmo cabeçalho.
    expect(container.text()).toContain('Estamos conectados');
    expect(container.text()).not.toContain('Estamos ausentes no momento');
  });
});
