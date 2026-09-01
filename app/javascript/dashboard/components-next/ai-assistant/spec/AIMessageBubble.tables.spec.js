import { describe, it, expect, vi } from 'vitest';
import { ref, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';

const mockReducedMotion = ref(false);
vi.mock('dashboard/composables/useReducedMotion', () => ({
  useReducedMotion: () => ({ prefersReducedMotion: mockReducedMotion }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn() },
}));

// O sanitizador do `useMarkdown` (arquivo do worker A4) hoje remove as tags de
// tabela, então a tabela nunca chega até aqui pelo caminho real. Este spec
// isola a DECORAÇÃO, que é responsabilidade deste componente: dado um HTML com
// <table>, ele precisa embrulhá-la numa caixa que rola sozinha. Quando o A4
// liberar as tags no allowlist, o caminho real passa a exercitar o mesmo
// código — sem precisar mexer neste teste.
vi.mock('../composables/useMarkdown', () => ({
  useMarkdown: () => ({
    html: ref(
      '<p>Comparativo:</p><table><thead><tr><th>Ação</th><th>Vantagem</th></tr></thead>' +
        '<tbody><tr><td>Aguardar</td><td>Sem custo</td></tr></tbody></table>'
    ),
  }),
}));

import AIMessageBubble from '../AIMessageBubble.vue';

describe('AIMessageBubble — tabela do markdown', () => {
  it('embrulha a tabela numa caixa com rolagem própria, para não empurrar a coluna', async () => {
    const wrapper = mount(AIMessageBubble, {
      props: { type: 'assistant', text: 'qualquer coisa' },
      attachTo: document.body,
    });
    await flushPromises();
    await nextTick();

    const wrap = wrapper.find('.oa-tablewrap');
    expect(wrap.exists()).toBe(true);

    const table = wrap.find('table');
    expect(table.exists()).toBe(true);
    // A tabela é filha do wrapper: quem rola é a caixa, não a coluna do chat.
    expect(table.element.parentElement).toBe(wrap.element);

    // O conteúdo das células continua estruturado (não virou texto corrido).
    expect(wrap.findAll('th')).toHaveLength(2);
    expect(wrap.findAll('td')).toHaveLength(2);

    wrapper.unmount();
  });

  it('não embrulha duas vezes quando o markdown re-renderiza', async () => {
    const wrapper = mount(AIMessageBubble, {
      props: { type: 'assistant', text: 'a' },
      attachTo: document.body,
    });
    await flushPromises();
    await nextTick();

    await wrapper.setProps({ text: 'b' });
    await flushPromises();
    await nextTick();

    expect(wrapper.findAll('.oa-tablewrap')).toHaveLength(1);
    wrapper.unmount();
  });
});
