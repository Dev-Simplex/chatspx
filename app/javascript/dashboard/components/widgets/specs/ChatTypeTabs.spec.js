import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';
import ChatTypeTabs from '../ChatTypeTabs.vue';
import Tabs from 'dashboard/components/ui/Tabs/Tabs.vue';
import TabsItem from 'dashboard/components/ui/Tabs/TabsItem.vue';

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

describe('ChatTypeTabs', () => {
  const items = [
    { key: 'me', name: 'Mine', count: 1, icon: 'i-lucide-user' },
    {
      key: 'unassigned',
      name: 'Unassigned',
      count: 2,
      icon: 'i-lucide-user-round-x',
      variant: 'alert',
    },
    { key: 'ai', name: 'AI', count: 3, icon: 'i-lucide-bot' },
    { key: 'all', name: 'All', count: 4, icon: 'i-lucide-users' },
  ];

  it('renders one tab per item', () => {
    const wrapper = mountComponent(items);
    expect(wrapper.findAllComponents(TabsItem).length).toBe(4);
  });

  it('groups queue tabs (awaiting/ai) on a second row via a flex row-break', () => {
    // me, all (primary, row 1) + awaiting, ai (queue, row 2)
    const wrapper = mountComponent([
      { key: 'me', name: 'Mine', count: 1, icon: 'i-lucide-user' },
      { key: 'awaiting', name: 'Awaiting', count: 2, icon: 'i-lucide-clock' },
      { key: 'ai', name: 'AI', count: 3, icon: 'i-lucide-sparkles' },
      { key: 'all', name: 'All', count: 4, icon: 'i-lucide-users' },
    ]);
    const breaks = wrapper.findAll('.wa-tab-row-break');
    expect(breaks.length).toBe(1);
    // Rendered order: me, all (primary) | break | awaiting, ai (queue)
    const tabNames = wrapper
      .findAllComponents(TabsItem)
      .map(c => c.props('name'));
    expect(tabNames).toEqual(['Mine', 'All', 'Awaiting', 'AI']);
  });

  it('does not render a row-break when there are no queue tabs (single row)', () => {
    const wrapper = mountComponent([
      { key: 'me', name: 'Mine', count: 1, icon: 'i-lucide-user' },
      { key: 'all', name: 'All', count: 4, icon: 'i-lucide-users' },
    ]);
    expect(wrapper.findAll('.wa-tab-row-break').length).toBe(0);
  });

  it('applies the tab-alert class only to items with the alert variant', () => {
    const wrapper = mountComponent(items);
    const tabs = wrapper.findAllComponents(TabsItem);
    // Reordered: me, unassigned, all (primary) | ai (queue)
    expect(tabs[0].classes()).not.toContain('tab-alert'); // me
    expect(tabs[1].classes()).toContain('tab-alert'); // unassigned
    expect(tabs[2].classes()).not.toContain('tab-alert'); // all
    expect(tabs[3].classes()).not.toContain('tab-alert'); // ai
  });

  it('does not apply tab-alert when no item carries the alert variant', () => {
    const wrapper = mountComponent([
      { key: 'me', name: 'Mine', count: 1, icon: 'i-lucide-user' },
      { key: 'all', name: 'All', count: 4, icon: 'i-lucide-users' },
    ]);
    expect(wrapper.findAll('.tab-alert').length).toBe(0);
  });

  it('emits chatTabChange with the item key on tab click', async () => {
    const wrapper = mountComponent(items);
    // Reordered order of buttons: me, unassigned, all, ai → index 3 is 'ai'
    await wrapper.findAll('button[role="tab"]')[3].trigger('click');
    expect(wrapper.emitted('chatTabChange')[0]).toEqual(['ai']);
  });

  it('keeps the active tab correct after reordering (active follows key)', () => {
    const wrapper = mountComponent(items, 'ai');
    const tabs = wrapper.findAllComponents(TabsItem);
    // 'ai' is the last (queue) tab after reordering — index 3
    expect(tabs[3].props('name')).toBe('AI');
    const activeButton = wrapper.find('button[aria-selected="true"]');
    expect(activeButton.text()).toContain('AI');
  });
});
