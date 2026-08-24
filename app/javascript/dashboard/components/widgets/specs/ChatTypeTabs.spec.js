import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';
import ChatTypeTabs from '../ChatTypeTabs.vue';
import Tabs from 'dashboard/components/ui/Tabs/Tabs.vue';
import TabsItem from 'dashboard/components/ui/Tabs/TabsItem.vue';

// ChatSPX: este arquivo foi reescrito porque descrevia um design que o componente NAO tem.
//
//   1. cobrava um elemento `.wa-tab-row-break` no DOM. A quebra e `flex-wrap` natural
//      ([&_ul]:flex-wrap), nao um no — nao existe o que procurar;
//   2. tratava `ai` como aba de FILA. `QUEUE_KEYS` e `[AWAITING, PENDING_CLOSURE]`; a IA fica
//      na linha 1, junto de Minhas e Todas;
//   3. o fixture compartilhado tinha UMA fila so, e o componente so reagrupa com 2+ filas
//      (regra dinamica documentada no .vue). Ou seja: os exemplos que diziam medir
//      reordenacao rodavam com a reordenacao DESLIGADA — dois deles passavam por acaso,
//      porque a aba com `alert` calha de ficar no mesmo indice nas duas ordens.
//
// Agora cada exemplo estabelece a condicao que o nome dele anuncia.

const mountComponent = (items, activeTab = 'me') =>
  mount(ChatTypeTabs, {
    props: { items, activeTab },
    global: {
      components: {
        'woot-tabs': Tabs,
        'woot-tabs-item': TabsItem,
      },
    },
  });

const aba = (key, name, extras = {}) => ({
  key,
  name,
  count: 1,
  icon: 'i-lucide-circle',
  ...extras,
});

// Duas filas (awaiting + pending_closure) => reagrupamento LIGADO.
// `awaiting` vem no meio de proposito: e o que prova que houve reordenacao.
const comDuasFilas = [
  aba('me', 'Mine'),
  aba('awaiting', 'Awaiting'),
  aba('unassigned', 'Unassigned', { variant: 'alert' }),
  aba('ai', 'AI'),
  aba('all', 'All'),
  aba('pending_closure', 'Pending closure'),
];

// Uma fila so => reagrupamento DESLIGADO, ordem natural preservada.
const comUmaFila = [
  aba('me', 'Mine'),
  aba('awaiting', 'Awaiting'),
  aba('ai', 'AI'),
  aba('all', 'All'),
];

const nomesRenderizados = wrapper =>
  wrapper.findAllComponents(TabsItem).map(c => c.props('name'));

describe('ChatTypeTabs', () => {
  it('renders one tab per item', () => {
    const wrapper = mountComponent(comDuasFilas);
    expect(wrapper.findAllComponents(TabsItem).length).toBe(
      comDuasFilas.length
    );
  });

  it('moves the queue tabs to the end when there are two or more of them', () => {
    const wrapper = mountComponent(comDuasFilas);
    expect(nomesRenderizados(wrapper)).toEqual([
      'Mine',
      'Unassigned',
      'AI',
      'All',
      'Awaiting',
      'Pending closure',
    ]);
  });

  it('keeps the natural order when there is a single queue tab', () => {
    const wrapper = mountComponent(comUmaFila);
    expect(nomesRenderizados(wrapper)).toEqual([
      'Mine',
      'Awaiting',
      'AI',
      'All',
    ]);
  });

  it('applies the tab-alert class only to items with the alert variant', () => {
    const wrapper = mountComponent(comDuasFilas);
    const tabs = wrapper.findAllComponents(TabsItem);
    const comAlerta = tabs
      .filter(t => t.classes().includes('tab-alert'))
      .map(t => t.props('name'));
    expect(comAlerta).toEqual(['Unassigned']);
  });

  it('does not apply tab-alert when no item carries the alert variant', () => {
    const wrapper = mountComponent([aba('me', 'Mine'), aba('all', 'All')]);
    expect(wrapper.findAll('.tab-alert').length).toBe(0);
  });

  it('emits chatTabChange with the key of the tab that was clicked, after reordering', async () => {
    const wrapper = mountComponent(comDuasFilas);
    // Depois da reordenacao a ultima aba e `pending_closure`, que no array de entrada
    // tambem era a ultima; a que prova o mapeamento e `Awaiting`, que saiu do indice 1
    // para o 4. Clicar no indice 4 tem de emitir 'awaiting', nao 'all'.
    await wrapper.findAll('button[role="tab"]')[4].trigger('click');
    expect(wrapper.emitted('chatTabChange')[0]).toEqual(['awaiting']);
  });

  it('does not emit when the clicked tab is already the active one', async () => {
    const wrapper = mountComponent(comDuasFilas, 'me');
    await wrapper.findAll('button[role="tab"]')[0].trigger('click');
    expect(wrapper.emitted('chatTabChange')).toBeUndefined();
  });

  it('keeps the active tab correct after reordering (active follows key)', () => {
    const wrapper = mountComponent(comDuasFilas, 'awaiting');
    const tabs = wrapper.findAllComponents(TabsItem);
    expect(tabs[4].props('name')).toBe('Awaiting');
    const ativa = wrapper.find('button[aria-selected="true"]');
    expect(ativa.text()).toContain('Awaiting');
  });
});
