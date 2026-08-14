import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';

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

import AIErrorBanner from '../AIErrorBanner.vue';

const TYPES = [
  ['unauthorized', 'ai-error-banner-unauthorized'],
  ['rate_limit', 'ai-error-banner-rate-limit'],
  ['captain_unstable', 'ai-error-banner-captain-unstable'],
  ['timeout', 'ai-error-banner-timeout'],
  ['empty_response', 'ai-error-banner-empty'],
  ['network', 'ai-error-banner-network'],
];

describe('AIErrorBanner — sóbrio e monocromático', () => {
  it.each(TYPES)('renderiza a variante %s com o testid estável', (type, id) => {
    const wrapper = mount(AIErrorBanner, { props: { errorType: type } });
    expect(wrapper.find(`[data-testid="${id}"]`).exists()).toBe(true);
  });

  it('não usa vermelho nem âmbar em nenhuma variante — só os tokens --oa-*', () => {
    TYPES.forEach(([type]) => {
      const html = mount(AIErrorBanner, {
        props: { errorType: type },
      }).html();
      expect(html).not.toMatch(/red-\d/);
      expect(html).not.toMatch(/amber-\d/);
      expect(html).not.toMatch(/purple-\d/);
      expect(html).toContain('bg-[var(--oa-code)]');
      expect(html).toContain('border-[var(--oa-line)]');
    });
  });

  it('a variante do 401 é a mais explícita e oferece tentar de novo', () => {
    const wrapper = mount(AIErrorBanner, {
      props: { errorType: 'unauthorized' },
    });
    expect(wrapper.text()).toContain(
      'CONVERSATION.COPILOT_ERRORS.UNAUTHORIZED.TITLE'
    );
    expect(wrapper.find('[data-testid="ai-error-banner-retry"]').exists()).toBe(
      true
    );
  });

  it('não renderiza nada para um tipo desconhecido', () => {
    const wrapper = mount(AIErrorBanner, { props: { errorType: 'whatever' } });
    expect(wrapper.html()).toBe('<!--v-if-->');
  });

  it('expõe role=alert e aria-live assertivo só para queda de rede', () => {
    const network = mount(AIErrorBanner, { props: { errorType: 'network' } });
    expect(
      network
        .find('[data-testid="ai-error-banner-network"]')
        .attributes('aria-live')
    ).toBe('assertive');

    const timeout = mount(AIErrorBanner, { props: { errorType: 'timeout' } });
    expect(
      timeout
        .find('[data-testid="ai-error-banner-timeout"]')
        .attributes('aria-live')
    ).toBe('polite');
  });

  it('emite retry, dismiss e cancel', async () => {
    const wrapper = mount(AIErrorBanner, {
      props: { errorType: 'captain_unstable' },
    });
    await wrapper
      .find('[data-testid="ai-error-banner-retry"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="ai-error-banner-dismiss"]')
      .trigger('click');
    expect(wrapper.emitted('retry')).toBeTruthy();
    expect(wrapper.emitted('dismiss')).toBeTruthy();

    const timeout = mount(AIErrorBanner, { props: { errorType: 'timeout' } });
    await timeout
      .find('[data-testid="ai-error-banner-cancel"]')
      .trigger('click');
    expect(timeout.emitted('cancel')).toBeTruthy();
  });

  it('recuperar e descartar não têm o mesmo peso', () => {
    // Os dois links iguais (semibold, --oa-ink) faziam "Tentar de novo" e
    // "Fechar" competirem. A ação que resolve fica forte; a que só sai de cena
    // fica em --oa-ink-2 — a mesma gradação do AISmartBanner.
    const wrapper = mount(AIErrorBanner, { props: { errorType: 'timeout' } });
    const primary = wrapper.find('[data-testid="ai-error-banner-retry"]');
    const secondary = wrapper.find('[data-testid="ai-error-banner-cancel"]');

    expect(primary.attributes('class')).toContain('font-semibold');
    expect(primary.attributes('class')).toContain('text-[var(--oa-ink)]');

    expect(secondary.attributes('class')).toContain('font-medium');
    expect(secondary.attributes('class')).toContain('text-[var(--oa-ink-2)]');
    expect(secondary.attributes('class')).not.toContain('font-semibold');

    // Nenhum dos dois abandona o sublinhado: continuam lendo como ação.
    expect(primary.attributes('class')).toContain('underline');
    expect(secondary.attributes('class')).toContain('underline');
  });

  it('dá 44x44 de área clicável a cada ação sem engordar o link', () => {
    const wrapper = mount(AIErrorBanner, { props: { errorType: 'timeout' } });
    ['retry', 'cancel'].forEach(action => {
      const button = wrapper.find(`[data-testid="ai-error-banner-${action}"]`);
      expect(button.attributes('class')).toContain('oa-hit-44');
      // O link segue sendo link: sem padding próprio, sem altura fixa.
      expect(button.attributes('class')).toContain('p-0');
    });
    // `gap-y-6` (24px) mantém 44px de passo se as ações quebrarem de linha —
    // sem ele duas áreas de toque de 44px se sobreporiam.
    const row = wrapper.find('[data-testid="ai-error-banner-retry"]').element
      .parentElement.className;
    expect(row).toContain('gap-y-6');
  });

  it('desabilita o retry enquanto o rate limit está em contagem', () => {
    const wrapper = mount(AIErrorBanner, {
      props: { errorType: 'rate_limit', retryAfterSeconds: 42 },
    });
    const retry = wrapper.find('[data-testid="ai-error-banner-retry"]');
    expect(retry.attributes('disabled')).toBeDefined();
    expect(retry.text()).toContain('"seconds":42');

    // "Aguarde 42s" é informação que o agente precisa ler: o desabilitado não
    // pode apagá-la. Sem `disabled:opacity-100` a global de `_base.scss:286`
    // deixa esse texto em 3,59:1.
    const cls = retry.attributes('class');
    expect(cls).toContain('disabled:opacity-100');
    expect(cls).toContain('disabled:text-[var(--oa-ink-2)]');
    expect(cls).not.toContain('disabled:opacity-50');
  });
});
