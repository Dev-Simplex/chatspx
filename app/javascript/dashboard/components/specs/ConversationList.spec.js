import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import ConversationList from '../ConversationList.vue';

// O composable só liga atalhos de teclado a um ref de DOM — irrelevante para este contrato.
vi.mock('dashboard/composables/chatlist/useChatListKeyboardEvents', () => ({
  useChatListKeyboardEvents: () => {},
}));

// A Virtualizer real usa ResizeObserver e não roda em jsdom; o mock apenas repassa o slot para
// cada item, que é tudo de que este contrato precisa. (Stub por nome não pega: em <script setup>
// o componente é um binding importado, não um registro global.)
vi.mock('virtua/vue', () => ({
  Virtualizer: {
    name: 'Virtualizer',
    props: ['data'],
    template: '<div><slot v-for="item in data" :item="item" /></div>',
  },
}));

const ConversationItemStub = {
  name: 'ConversationItem',
  props: ['source', 'showExpanded', 'showAssignee'],
  template: '<div class="conversation-item-stub" />',
};

const mountList = (props = {}) =>
  mount(ConversationList, {
    props: {
      conversationList: [{ id: 1 }],
      ...props,
    },
    global: {
      stubs: {
        ConversationItem: ConversationItemStub,
        Spinner: true,
        IntersectionObserver: true,
      },
    },
  });

// ChatSPX (A4-1): o ConversationCardExpanded do upstream não implementa o isolamento por agente —
// em tela larga com layout expandido o preview de uma mensagem restrita a OUTRO agente apareceria
// em texto cru, sem o 🔒. Enquanto a Opção A estiver em vigor, a lista tem de usar SEMPRE o nosso
// ConversationCard, inclusive com isOnExpandedLayout=true e viewport larga.
describe('ConversationList — isolamento por agente (A4-1)', () => {
  it('never asks ConversationItem for the expanded card, even on an expanded layout', () => {
    window.innerWidth = 1440;

    const wrapper = mountList({ isOnExpandedLayout: true });

    const item = wrapper.findComponent(ConversationItemStub);
    expect(item.exists()).toBe(true);
    expect(item.props('showExpanded')).toBe(false);
  });

  it('keeps showExpanded false on a narrow layout too', () => {
    window.innerWidth = 480;

    const wrapper = mountList({ isOnExpandedLayout: false });

    expect(
      wrapper.findComponent(ConversationItemStub).props('showExpanded')
    ).toBe(false);
  });
});
