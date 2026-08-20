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

  it('groups awaiting queues after the primary tabs for natural wrapping', () => {
    const wrapper = mountComponent([
      { key: 'me', name: 'Mine', count: 1, icon: 'i-lucide-user' },
      { key: 'awaiting', name: 'Awaiting', count: 2, icon: 'i-lucide-clock' },
      {
        key: 'pending_closure',
        name: 'Pending closure',
        count: 2,
        icon: 'i-lucide-clock',
      },
      { key: 'ai', name: 'AI', count: 3, icon: 'i-lucide-sparkles' },
      { key: 'all', name: 'All', count: 4, icon: 'i-lucide-users' },
    ]);
    expect(wrapper.findAll('.wa-tab-row-break').length).toBe(0);
    const tabNames = wrapper
      .findAllComponents(TabsItem)
      .map(c => c.props('name'));
    expect(tabNames).toEqual([
      'Mine',
      'AI',
      'All',
      'Awaiting',
      'Pending closure',
    ]);
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
    expect(tabs[0].classes()).not.toContain('tab-alert'); // me
    expect(tabs[1].classes()).toContain('tab-alert'); // unassigned
    expect(tabs[2].classes()).not.toContain('tab-alert'); // ai
    expect(tabs[3].classes()).not.toContain('tab-alert'); // all
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
    await wrapper.findAll('button[role="tab"]')[2].trigger('click');
    expect(wrapper.emitted('chatTabChange')[0]).toEqual(['ai']);
  });

  it('keeps the active tab correct after reordering (active follows key)', () => {
    const wrapper = mountComponent(items, 'ai');
    const tabs = wrapper.findAllComponents(TabsItem);
    expect(tabs[2].props('name')).toBe('AI');
    const activeButton = wrapper.find('button[aria-selected="true"]');
    expect(activeButton.text()).toContain('AI');
  });
});
