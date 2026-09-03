import { mount } from '@vue/test-utils';
import WidgetTeaser from '../components/WidgetTeaser.vue';

/**
 * Bloco 4.07: o teaser configurado aparece no preview com **texto, avatar e
 * chips reais** — e as duas formas sao a MESMA coisa com peças escondidas, nao
 * dois componentes.
 */
const build = (props = {}) =>
  mount(WidgetTeaser, {
    props: {
      level: 'bold',
      text: 'Posso ajudar a escolher o plano?',
      senderName: 'Marina',
      intents: [
        { id: 'pricing', label: 'Preços' },
        { id: 'demo', label: 'Agendar demo' },
      ],
      ...props,
    },
    global: { stubs: { Avatar: true } },
  });

describe('WidgetTeaser', () => {
  it('Chamativo mostra texto, remetente, avatar e chips', () => {
    const wrapper = build();

    expect(wrapper.find('[data-testid="teaser-text"]').text()).toBe(
      'Posso ajudar a escolher o plano?'
    );
    expect(wrapper.find('[data-testid="teaser-sender"]').text()).toBe('Marina');
    expect(wrapper.find('[data-testid="teaser-avatar"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="teaser-chips"]').text()).toContain(
      'Preços'
    );
    expect(wrapper.find('[data-testid="teaser-chips"]').text()).toContain(
      'Agendar demo'
    );
  });

  it('Discreto é o mesmo balão sem foto e sem chips', () => {
    const wrapper = build({ level: 'discreet' });

    expect(wrapper.find('[data-testid="teaser-text"]').text()).toBe(
      'Posso ajudar a escolher o plano?'
    );
    expect(wrapper.find('[data-testid="teaser-avatar"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="teaser-chips"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="teaser-sender"]').exists()).toBe(false);
  });

  it('no máximo 4 chips — acima disso vira menu, não convite', () => {
    const wrapper = build({
      intents: [
        { id: 'a', label: 'Um' },
        { id: 'b', label: 'Dois' },
        { id: 'c', label: 'Três' },
        { id: 'd', label: 'Quatro' },
        { id: 'e', label: 'Cinco' },
      ],
    });

    expect(
      wrapper.find('[data-testid="teaser-chips"]').findAll('span')
    ).toHaveLength(4);
    expect(wrapper.find('[data-testid="teaser-chips"]').text()).not.toContain(
      'Cinco'
    );
  });

  it('sem texto não há teaser — balão vazio no site do cliente é pior que nenhum', () => {
    expect(
      build({ text: '' }).find('[data-testid="teaser-bold"]').exists()
    ).toBe(false);
  });

  it('usa os tokens da marca, nunca cor literal', () => {
    const html = build().html();

    expect(html).toContain('bg-w-brand');
    expect(html).toContain('text-w-on-brand');
    expect(html).not.toMatch(/#[0-9a-f]{6}/i);
  });
});
