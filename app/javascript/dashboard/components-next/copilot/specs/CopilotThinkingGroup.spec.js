import { shallowMount } from '@vue/test-utils';
import CopilotThinkingGroup from '../CopilotThinkingGroup.vue';

const { localeRef } = vi.hoisted(() => ({
  localeRef: { value: 'pt_BR' },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    locale: localeRef,
    t: (key, params = {}) => {
      const tools = {
        'CAPTAIN.COPILOT.THINKING.TOOLS.GET_CONVERSATION': 'conversa',
        'CAPTAIN.COPILOT.THINKING.TOOLS.SEARCH_CONVERSATION': 'conversas',
        'CAPTAIN.COPILOT.THINKING.TOOLS.SEARCH_CONTACTS': 'contatos',
        'CAPTAIN.COPILOT.THINKING.TOOLS.GET_CONTACT': 'contato',
        'CAPTAIN.COPILOT.THINKING.TOOLS.SEARCH_ARTICLES': 'artigos',
        'CAPTAIN.COPILOT.THINKING.TOOLS.GET_ARTICLE': 'artigo',
        'CAPTAIN.COPILOT.THINKING.TOOLS.SEARCH_DOCUMENTATION':
          'base de conhecimento',
        'CAPTAIN.COPILOT.THINKING.TOOLS.SEARCH_LINEAR_ISSUES': 'tarefas',
        'CAPTAIN.COPILOT.THINKING.TOOLS.FALLBACK': 'informações',
      };

      if (key === 'CAPTAIN.COPILOT.THINKING.STARTED') {
        return `Buscando ${params.target}...`;
      }

      if (key === 'CAPTAIN.COPILOT.THINKING.COMPLETED') {
        return `Busca concluída: ${params.target}.`;
      }

      if (tools[key]) {
        return tools[key];
      }

      if (key === 'CAPTAIN.COPILOT.SHOW_STEPS') {
        return 'Mostrar etapas';
      }

      return key;
    },
  }),
}));

const CopilotThinkingBlockStub = {
  name: 'CopilotThinkingBlock',
  props: ['content'],
  template: '<div class="thinking-content">{{ content }}</div>',
};

let messageId = 0;
const buildThinkingMessage = message => {
  messageId += 1;
  return {
    id: messageId,
    message,
  };
};

const mountComponent = messages => {
  return shallowMount(CopilotThinkingGroup, {
    props: {
      messages,
    },
    global: {
      stubs: {
        Icon: true,
        CopilotThinkingBlock: CopilotThinkingBlockStub,
      },
    },
  });
};

describe('CopilotThinkingGroup', () => {
  beforeEach(() => {
    messageId = 0;
    localeRef.value = 'pt_BR';
  });

  it('formats legacy "Using get_conversation" message in PT-BR', () => {
    const wrapper = mountComponent([
      buildThinkingMessage({ content: 'Using get_conversation' }),
    ]);

    expect(wrapper.find('.thinking-content').text()).toBe(
      'Buscando conversa...'
    );
  });

  it('formats legacy "Completed get_conversation" message in PT-BR', () => {
    const wrapper = mountComponent([
      buildThinkingMessage({ content: 'Completed get_conversation' }),
    ]);

    expect(wrapper.find('.thinking-content').text()).toBe(
      'Busca concluída: conversa.'
    );
  });

  it('formats new started event using tool_event and function_name', () => {
    const wrapper = mountComponent([
      buildThinkingMessage({
        content: 'Using search_contacts',
        function_name: 'search_contacts',
        tool_event: 'started',
      }),
    ]);

    expect(wrapper.find('.thinking-content').text()).toBe(
      'Buscando contatos...'
    );
  });

  it('formats new completed event using tool_event and function_name', () => {
    const wrapper = mountComponent([
      buildThinkingMessage({
        content: 'Completed get_contact',
        function_name: 'get_contact',
        tool_event: 'completed',
      }),
    ]);

    expect(wrapper.find('.thinking-content').text()).toBe(
      'Busca concluída: contato.'
    );
  });

  it('uses friendly fallback for unknown tools', () => {
    const wrapper = mountComponent([
      buildThinkingMessage({
        content: 'Using unknown_tool',
        function_name: 'unknown_tool',
        tool_event: 'started',
      }),
    ]);

    expect(wrapper.find('.thinking-content').text()).toBe(
      'Buscando informações...'
    );
  });

  it('keeps original content for non-pt_BR locales', () => {
    localeRef.value = 'en';

    const wrapper = mountComponent([
      buildThinkingMessage({ content: 'Using get_conversation' }),
    ]);

    expect(wrapper.find('.thinking-content').text()).toBe(
      'Using get_conversation'
    );
  });
});
