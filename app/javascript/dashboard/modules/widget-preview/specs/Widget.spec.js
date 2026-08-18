import { mount } from '@vue/test-utils';
import Widget from '../components/Widget.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { logoThumbnail: '/logo.png' } }),
  useStore: () => ({ getters: {}, dispatch: vi.fn() }),
}));

const build = (props = {}) =>
  mount(Widget, {
    props: { websiteName: 'Simplex', color: '#2dc46f', ...props },
    global: { stubs: { Code: true, TabBar: true } },
  });

const surface = wrapper =>
  wrapper.find('[data-testid="widget-preview-surface"]');

afterEach(() => document.documentElement.classList.remove('dark'));

describe('preview do widget — tema próprio', () => {
  it('nasce claro e aplica os tokens DERIVADOS da cor, não a cor crua', () => {
    const wrapper = build();
    const style = surface(wrapper).attributes('style');

    expect(surface(wrapper).classes()).toContain('wp-theme-light');
    expect(style).toContain('--w-brand: #2dc46f');
    // o verde da marca com texto BRANCO daria 2,27:1 — o preview mostra o preto
    expect(style).toContain('--w-on-brand: #000000');
    expect(style).toContain('--w-brand-readable: #1d824a');
  });

  it('o toggle escurece o preview SEM o dashboard estar escuro', async () => {
    const wrapper = build();
    expect(document.documentElement.classList.contains('dark')).toBe(false);

    await wrapper.find('[data-testid="preview-theme-toggle"]').trigger('click');

    expect(surface(wrapper).classes()).toContain('wp-theme-dark');
    expect(surface(wrapper).classes()).not.toContain('wp-theme-light');
  });

  it('o dashboard escuro NÃO escurece o preview sozinho', async () => {
    const wrapper = build();

    document.documentElement.classList.add('dark');
    await wrapper.vm.$nextTick();

    expect(surface(wrapper).classes()).toContain('wp-theme-light');
  });

  it('inbox configurada em `dark` abre o preview escuro', () => {
    const wrapper = build({ themeMode: 'dark' });

    expect(surface(wrapper).classes()).toContain('wp-theme-dark');
  });

  it('`auto` abre no claro, e continua alcançável pelo toggle', async () => {
    const wrapper = build({ themeMode: 'auto' });
    expect(surface(wrapper).classes()).toContain('wp-theme-light');

    await wrapper.find('[data-testid="preview-theme-toggle"]').trigger('click');

    expect(surface(wrapper).classes()).toContain('wp-theme-dark');
  });
});

describe('preview do widget — o que a tela de aparência configura', () => {
  it('o toggle de celular estreita a superfície', async () => {
    const wrapper = build();
    expect(wrapper.find('.widget-wrapper').classes()).toContain('w-80');

    await wrapper
      .find('[data-testid="preview-device-toggle"]')
      .trigger('click');

    expect(wrapper.find('.widget-wrapper').classes()).toContain('w-[22.5rem]');
  });

  it('esconder a bolha tira o lançador do preview', () => {
    expect(build().find('[data-testid="preview-launcher"]').exists()).toBe(
      true
    );
    expect(
      build({ hideBubble: true })
        .find('[data-testid="preview-launcher"]')
        .exists()
    ).toBe(false);
  });

  it('os offsets afastam o lançador das bordas', () => {
    const wrapper = build({ offsetX: 40, offsetY: 12 });
    const linha = wrapper.find('[data-testid="preview-launcher"]').element
      .parentElement;

    expect(linha.getAttribute('style')).toContain('padding-inline: 40px');
    expect(linha.getAttribute('style')).toContain('padding-bottom: 12px');
  });

  it('a posição esquerda muda o alinhamento do lançador', () => {
    const wrapper = build({ widgetBubblePosition: 'left' });
    const linha = wrapper.find('[data-testid="preview-launcher"]').element
      .parentElement;

    expect(linha.getAttribute('style')).toContain('justify-content: start');
  });
});
