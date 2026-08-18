import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ref, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';

const mockReducedMotion = ref(false);
vi.mock('dashboard/composables/useReducedMotion', () => ({
  useReducedMotion: () => ({ prefersReducedMotion: mockReducedMotion }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      if (params && Object.keys(params).length > 0) {
        return `${key}:${JSON.stringify(params)}`;
      }
      return key;
    },
  }),
}));

const toastSuccess = vi.fn();
const toastError = vi.fn();
vi.mock('vue-sonner', () => ({
  toast: {
    success: (...args) => toastSuccess(...args),
    error: (...args) => toastError(...args),
  },
}));

import AIMessageBubble from '../AIMessageBubble.vue';

const writeText = vi.fn(() => Promise.resolve());

describe('AIMessageBubble — linguagem visual OpenAI', () => {
  beforeEach(() => {
    mockReducedMotion.value = false;
    toastSuccess.mockClear();
    toastError.mockClear();
    writeText.mockClear();
    Object.defineProperty(global.navigator, 'clipboard', {
      value: { writeText },
      configurable: true,
      writable: true,
    });
  });

  // === A decisão estrutural: só o usuário tem bolha ===

  describe('papel user', () => {
    it('renderiza bolha cinza alinhada à direita, com raio 18px e teto de 75%', () => {
      const wrapper = mount(AIMessageBubble, {
        props: { type: 'user', text: 'O que devo fazer agora?' },
      });
      const bubble = wrapper.find('[data-testid="ai-message-bubble-user"]');
      expect(bubble.exists()).toBe(true);

      const cls = bubble.attributes('class');
      expect(cls).toContain('rounded-[18px]');
      expect(cls).toContain('bg-[var(--oa-user-bub)]');
      expect(cls).toContain('max-w-[75%]');

      // A linha inteira empurra a bolha para a direita.
      expect(wrapper.find('.justify-end').exists()).toBe(true);
      expect(wrapper.text()).toContain('O que devo fazer agora?');
    });

    it('não expõe ações nem corpo de markdown', () => {
      const wrapper = mount(AIMessageBubble, {
        props: { type: 'user', text: 'oi' },
      });
      expect(wrapper.find('[data-testid="ai-message-apply"]').exists()).toBe(
        false
      );
      expect(wrapper.find('[data-testid="ai-message-body"]').exists()).toBe(
        false
      );
    });
  });

  describe('papel assistant', () => {
    it('NÃO tem bolha: nada de fundo de bolha, raio 18px, avatar ou etiqueta', () => {
      const wrapper = mount(AIMessageBubble, {
        props: { type: 'assistant', text: 'Resposta da IA' },
      });
      const html = wrapper.html();

      expect(html).not.toContain('bg-[var(--oa-user-bub)]');
      expect(html).not.toContain('rounded-[18px]');
      // A etiqueta "Copilot" e o avatar de sparkles saíram do desenho.
      expect(wrapper.text()).not.toContain('Copilot');
      expect(html).not.toContain('i-lucide-sparkles');
    });

    it('ocupa a largura da coluna e usa a tipografia .oa-prose', () => {
      const wrapper = mount(AIMessageBubble, {
        props: { type: 'assistant', text: 'Resposta da IA' },
      });
      const body = wrapper.find('[data-testid="ai-message-body"]');
      expect(body.exists()).toBe(true);
      expect(body.attributes('class')).toContain('oa-prose');
      expect(
        wrapper.find('[data-testid="ai-message-bubble-assistant"]').classes()
      ).toContain('w-full');
    });

    it('renderiza markdown rico: parágrafo, lista e negrito', () => {
      const wrapper = mount(AIMessageBubble, {
        props: {
          type: 'assistant',
          text: 'Duas exceções:\n\n- **Defeito** — 90 dias\n- **Não entregue** — sem limite',
        },
      });
      const body = wrapper.find('[data-testid="ai-message-body"]');
      expect(body.findAll('li')).toHaveLength(2);
      expect(body.findAll('strong').length).toBeGreaterThanOrEqual(2);
    });
  });

  // === Bloco de código: rolagem própria + botão de copiar ===

  describe('bloco de código', () => {
    const CODE_TEXT = [
      '```',
      'curl -X POST https://exemplo/muito/longo',
      '```',
    ].join('\n');

    it('embrulha o <pre> e injeta o botão de copiar FORA do container de scroll', async () => {
      const wrapper = mount(AIMessageBubble, {
        props: { type: 'assistant', text: CODE_TEXT },
        attachTo: document.body,
      });
      await flushPromises();
      await nextTick();

      const wrap = wrapper.find('.oa-codeblock');
      expect(wrap.exists()).toBe(true);
      expect(wrap.find('pre').exists()).toBe(true);

      const button = wrapper.find('[data-testid="ai-code-copy"]');
      expect(button.exists()).toBe(true);
      // O botão é irmão do <pre>, não filho dele: o <pre> é quem rola.
      expect(button.element.parentElement).toBe(wrap.element);
      wrapper.unmount();
    });

    it('copia o conteúdo do bloco ao clicar', async () => {
      const wrapper = mount(AIMessageBubble, {
        props: { type: 'assistant', text: CODE_TEXT },
        attachTo: document.body,
      });
      await flushPromises();
      await nextTick();

      await wrapper.find('[data-testid="ai-code-copy"]').trigger('click');
      await flushPromises();

      expect(writeText).toHaveBeenCalledTimes(1);
      expect(writeText.mock.calls[0][0]).toContain('curl -X POST');
      wrapper.unmount();
    });
  });

  // === Ações abaixo da resposta ===

  describe('ações', () => {
    const mountAssistant = () =>
      mount(AIMessageBubble, {
        props: { type: 'assistant', text: 'texto gerado' },
      });

    it('mostra a ação primária + 4 ícones discretos de 36x36 com alvo de 44', () => {
      const wrapper = mountAssistant();
      const apply = wrapper.find('[data-testid="ai-message-apply"]');
      expect(apply.exists()).toBe(true);
      expect(apply.attributes('class')).toContain('oa-hit-44');

      const icons = [
        'ai-message-copy',
        'ai-message-retry',
        'ai-message-feedback-up',
        'ai-message-feedback-down',
      ];
      icons.forEach(id => {
        const button = wrapper.find(`[data-testid="${id}"]`);
        expect(button.exists()).toBe(true);
        // 36px visíveis: 36 + gap-2 (8px) = 44 de passo, o mínimo para as
        // áreas de toque de `oa-hit-44` encostarem sem se sobrepor.
        expect(button.attributes('class')).toContain('size-9');
        expect(button.attributes('class')).toContain('oa-hit-44');
        // Ícone sozinho precisa de nome acessível.
        expect(button.attributes('aria-label')).toBeTruthy();
      });

      // O passo de 44px depende do gap do contêiner: travar aqui evita que
      // alguém volte para `gap-0.5` e reintroduza a sobreposição.
      expect(apply.element.parentElement.className).toContain('gap-2');
    });

    it('a borda dos botões volta a existir (border-solid vence _base.scss)', () => {
      // `_base.scss` aplica `border-0 border-none` a TODO <button> do produto
      // e a classe `.border` do Tailwind só define a largura — sem
      // `border-solid` o contorno some (medido: 1,00:1 contra o fundo).
      const streaming = mount(AIMessageBubble, {
        props: { type: 'assistant', text: 'parcial', isStreaming: true },
      });
      const stop = streaming.find('[data-testid="ai-message-stop"]');
      expect(stop.attributes('class')).toContain('border-solid');

      const wrapper = mount(AIMessageBubble, {
        props: {
          type: 'assistant',
          text: 'texto gerado',
          sources: ['Política Comercial'],
        },
      });
      const chip = wrapper.find('[data-testid="ai-message-source"]');
      expect(chip.attributes('class')).toContain('border-solid');
      expect(chip.attributes('class')).toContain('oa-hit-44');
    });

    it('emite apply com o texto ao clicar em "Usar como resposta"', async () => {
      const wrapper = mountAssistant();
      await wrapper.find('[data-testid="ai-message-apply"]').trigger('click');
      expect(wrapper.emitted('apply')).toBeTruthy();
      expect(wrapper.emitted('apply')[0][0]).toBe('texto gerado');
    });

    it('emite copy e escreve na área de transferência', async () => {
      const wrapper = mountAssistant();
      await wrapper.find('[data-testid="ai-message-copy"]').trigger('click');
      await flushPromises();
      expect(writeText).toHaveBeenCalledWith('texto gerado');
      expect(wrapper.emitted('copy')).toBeTruthy();
    });

    it('emite retry', async () => {
      const wrapper = mountAssistant();
      await wrapper.find('[data-testid="ai-message-retry"]').trigger('click');
      expect(wrapper.emitted('retry')).toBeTruthy();
    });

    it('emite feedback up/down', async () => {
      const wrapper = mountAssistant();
      await wrapper
        .find('[data-testid="ai-message-feedback-up"]')
        .trigger('click');
      expect(wrapper.emitted('feedback')[0][0]).toBe('up');

      const other = mountAssistant();
      await other
        .find('[data-testid="ai-message-feedback-down"]')
        .trigger('click');
      expect(other.emitted('feedback')[0][0]).toBe('down');
    });

    it('não emite duas vezes em clique duplo acidental (debounce 300ms)', async () => {
      const wrapper = mountAssistant();
      const button = wrapper.find('[data-testid="ai-message-feedback-up"]');
      await button.trigger('click');
      await button.trigger('click');
      expect(wrapper.emitted('feedback')).toHaveLength(1);
    });
  });

  // === Streaming ===

  describe('streaming', () => {
    it('troca as ações por "Parar" e emite cancel-streaming', async () => {
      const wrapper = mount(AIMessageBubble, {
        props: { type: 'assistant', text: 'gerando...', isStreaming: true },
      });
      expect(wrapper.find('[data-testid="ai-message-apply"]').exists()).toBe(
        false
      );
      const stop = wrapper.find('[data-testid="ai-message-stop"]');
      expect(stop.exists()).toBe(true);
      await stop.trigger('click');
      expect(wrapper.emitted('cancel-streaming')).toBeTruthy();
    });

    it('mantém aria-live="off" durante o streaming para não inundar o leitor de tela', () => {
      const wrapper = mount(AIMessageBubble, {
        props: { type: 'assistant', text: 'gerando...', isStreaming: true },
      });
      expect(
        wrapper.find('[data-testid="ai-message-body"]').attributes('aria-live')
      ).toBe('off');
    });
  });

  // === Fonte citada ===

  describe('fonte citada', () => {
    it('renderiza um chip por fonte, aceitando string ou objeto', () => {
      const wrapper = mount(AIMessageBubble, {
        props: {
          type: 'assistant',
          text: 'resposta',
          sources: [
            'Política Comercial · seção 4.2',
            { id: 'p48291', label: 'Pedido #48291 · rastreio' },
          ],
        },
      });
      const chips = wrapper.findAll('[data-testid="ai-message-source"]');
      expect(chips).toHaveLength(2);
      expect(chips[0].text()).toContain('Política Comercial');
      expect(chips[1].text()).toContain('Pedido #48291');
    });

    it('emite source-click com a fonte original', async () => {
      const source = { id: 'p1', label: 'Pedido #1' };
      const wrapper = mount(AIMessageBubble, {
        props: { type: 'assistant', text: 'resposta', sources: [source] },
      });
      await wrapper.find('[data-testid="ai-message-source"]').trigger('click');
      expect(wrapper.emitted('source-click')[0][0]).toEqual(source);
    });

    it('não renderiza nada quando não há fonte', () => {
      const wrapper = mount(AIMessageBubble, {
        props: { type: 'assistant', text: 'resposta' },
      });
      expect(wrapper.find('[data-testid="ai-message-source"]').exists()).toBe(
        false
      );
    });
  });

  // === Carregando ===

  describe('papel thinking', () => {
    it('mostra três pontinhos (nunca um spinner) com role=status', () => {
      const wrapper = mount(AIMessageBubble, {
        props: { type: 'thinking', text: '' },
      });
      const root = wrapper.find('[data-testid="ai-message-bubble-thinking"]');
      expect(root.exists()).toBe(true);
      expect(root.attributes('role')).toBe('status');
      expect(wrapper.findAll('.oa-dot')).toHaveLength(3);
      expect(wrapper.html()).not.toContain('animate-spin');
    });
  });
});
