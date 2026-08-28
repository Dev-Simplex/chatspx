import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';

import ChatOption from 'shared/components/ChatOption.vue';
import UnreadMessageList from 'widget/components/UnreadMessageList.vue';
import TeamAvailability from 'widget/components/TeamAvailability.vue';
import ArticleBlock from 'widget/components/pageComponents/Home/Article/ArticleBlock.vue';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import en from 'widget/i18n/locale/en.json';

/**
 * BLOCOS 1.03/1.04 · W1.6 — "remover TODOS os `:style` de cor".
 *
 * O DEFEITO, e por que ele sobreviveu a três `grep` verdes: em `ChatOption` e
 * `UnreadMessageList` a classe do token JÁ TINHA SIDO aplicada — e o `:style`
 * inline, que ficou, VENCE a classe (inline > classe, sem `!important`). A
 * borda do chip e o rótulo de "ver mensagens" seguiam pintados com a MARCA
 * CRUA, a 2,27:1, com o aceite de nome verde.
 *
 * O QUE ESTE SPEC MEDE, E O QUE ELE NÃO MEDE
 *
 * Aqui é montagem REAL dos quatro componentes, com o getter REAL
 * (`appConfig/getWidgetColor`) devolvendo uma cor DIVERGENTE do token. A
 * divergência é o método: se qualquer um deles voltar a ler a cor por fora do
 * design system, ela aparece no atributo `style` e a asserção cai apontando o
 * valor. Um teste que só perguntasse "tem a classe?" passaria com o `:style`
 * vivo — foi exatamente assim que o defeito atravessou a auditoria anterior.
 *
 * A COR COMPUTADA — que é o que o visitante vê — não se mede em jsdom: ele não
 * resolve `@apply`, nem cascade, nem herança de folha injetada. Ela é medida em
 * Chromium por `specs/browser/marca-token-cor.check.mjs`, com o CSS do widget
 * compilado de verdade.
 */

// Vermelho puro: nenhum token de marca do widget resolve para isto, nem no tema
// claro (`#1d824a`) nem no escuro (`#2dc46f`). Se aparecer, veio do getter.
const MARCA_DIVERGENTE = '#ff0000';

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  fallbackLocale: 'en',
  messages: { pt_BR: ptBR, en },
});

const criarStore = () =>
  createStore({
    modules: {
      appConfig: {
        namespaced: true,
        getters: {
          getWidgetColor: () => MARCA_DIVERGENTE,
          getAvailableMessage: () => 'Estamos online',
          getUnavailableMessage: () => 'Voltamos logo',
        },
      },
      conversation: {
        namespaced: true,
        getters: { getUnreadMessageCount: () => 2 },
      },
    },
  });

const montar = (componente, props = {}) =>
  mount(componente, {
    props,
    global: {
      plugins: [criarStore(), i18n],
      stubs: {
        FluentIcon: true,
        UnreadMessage: true,
        AvailabilityContainer: true,
        ArticleListItem: true,
      },
    },
  });

/**
 * Toda declaração de cor que sobrou em `style=""`, do elemento e de todos os
 * descendentes. Nomeia o elemento para que a falha diga ONDE, não só QUE.
 *
 * Procura por PROPRIEDADE, não pelo valor: um `:style` que volte com outra cor
 * (a de hover, um cinza cravado) é o mesmo defeito de arquitetura, e um teste
 * que só procurasse `#ff0000` o deixaria passar.
 */
const coresInline = wrapper =>
  wrapper
    .findAll('[style]')
    .map(el => el.attributes('style') || '')
    .filter(style =>
      /(^|[;\s])(color|border-color|background-color)\s*:/.test(style)
    );

describe('nenhum :style de cor nas quatro superfícies da marca (W1.6)', () => {
  it('ChatOption — o chip de resposta rápida', () => {
    const wrapper = montar(ChatOption, {
      action: { title: 'Quero falar com um humano' },
    });

    expect(coresInline(wrapper)).toEqual([]);
  });

  it('ChatOption — borda e rótulo saem do token, não do getter', () => {
    const wrapper = montar(ChatOption, {
      action: { title: 'Quero falar com um humano' },
    });

    // A borda mora na regra escopada `.option`; o rótulo, em `.option-button`.
    // Ambas com `w-brand-readable`, e é isso que o Chromium confere depois.
    expect(wrapper.find('li').classes()).toContain('option');
    expect(wrapper.find('button').classes()).toContain('option-button');
    // O getter existe e devolve a cor divergente — a asserção acima só vale
    // porque a cor ESTAVA disponível e mesmo assim não foi usada.
    expect(wrapper.vm.$store.getters['appConfig/getWidgetColor']).toBe(
      MARCA_DIVERGENTE
    );
  });

  it('UnreadMessageList — o rótulo "ver mensagens"', () => {
    const wrapper = montar(UnreadMessageList, {
      messages: [
        {
          id: 1,
          content: 'Oi! Tudo bem?',
          messageType: 1,
          sender: { name: 'Marina' },
        },
      ],
    });

    expect(coresInline(wrapper)).toEqual([]);
    // A cor desce de `.clear-button`, que é `text-w-brand-readable`.
    expect(wrapper.find('.clear-button').exists()).toBe(true);
  });

  it('TeamAvailability — "iniciar conversa"', () => {
    const wrapper = montar(TeamAvailability, { availableAgents: [] });

    expect(coresInline(wrapper)).toEqual([]);
    expect(wrapper.find('button').classes()).toContain('text-w-brand-readable');
    // E a classe que o inline mascarava não pode ficar para trás: ela pintaria
    // o botão de cinza-texto, que não é a marca.
    expect(wrapper.find('button').classes()).not.toContain('text-n-slate-12');
  });

  it('ArticleBlock — "ver todos os artigos"', () => {
    const wrapper = montar(ArticleBlock, {
      articles: [{ slug: 'a', title: 'Como conectar', link: '/a' }],
    });

    expect(coresInline(wrapper)).toEqual([]);
    expect(wrapper.find('button').classes()).toContain('text-w-brand-readable');
  });
});
