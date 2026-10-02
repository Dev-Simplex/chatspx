import { mount } from '@vue/test-utils';
import CatalogProductCard from '../CatalogProductCard.vue';

const { escondidos } = vi.hoisted(() => ({ escondidos: [] }));

// Nome do item e campos escondidos vêm da conta; aqui a conta usa o padrão e o teste escolhe
// o que esconder.
vi.mock('dashboard/composables/useCatalogLabels', async () => {
  const { ref } = await import('vue');
  return {
    useCatalogLabels: () => ({
      labels: ref({ item: 'product', items: 'products' }),
      isFieldHidden: campo => escondidos.includes(campo),
    }),
  };
});

const produto = {
  id: 1,
  name: 'Ray-Ban Aviador Clássico',
  sku: 'RB3025-001',
  price_cents: 74900,
  promo_price_cents: 62900,
  current_price_cents: 62900,
  on_sale: true,
  currency: 'BRL',
  stock: 12,
  visible: true,
  featured: true,
  cover_url: 'https://exemplo.test/rb.jpg',
  meta_product_id: null,
  meta_synced_at: null,
};

const montar = (extra = {}, props = {}) =>
  mount(CatalogProductCard, {
    props: { produto: { ...produto, ...extra }, ...props },
  });

describe('CatalogProductCard', () => {
  beforeEach(() => {
    escondidos.length = 0;
  });

  it('não mostra preço quando o item não tem preço', () => {
    const wrapper = montar({
      price_cents: null,
      current_price_cents: null,
      on_sale: false,
    });

    expect(wrapper.find('[data-testid="card-preco"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('R$');
  });

  it('mostra até três campos personalizados, na ordem em que vieram', () => {
    const wrapper = montar({
      custom_fields: [
        { label: 'Dormitórios', value: '3' },
        { label: 'Bairro', value: 'Centro' },
        { label: 'Vagas', value: '2' },
        { label: 'Suítes', value: '1' },
      ],
    });

    expect(
      wrapper.findAll('[data-testid="card-campo"]').map(campo => campo.text())
    ).toEqual(['Dormitórios: 3', 'Bairro: Centro', 'Vagas: 2']);
  });

  it('some com SKU e estoque quando a conta esconde os dois', () => {
    escondidos.push('sku', 'stock');
    const wrapper = montar();

    expect(wrapper.find('[data-testid="card-sku"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="selo-estoque"]').exists()).toBe(false);
  });

  it('risca o preço cheio só quando existe promoção', () => {
    expect(montar().find('.line-through').exists()).toBe(true);
    expect(
      montar({ on_sale: false, current_price_cents: 74900 })
        .find('.line-through')
        .exists()
    ).toBe(false);
  });

  it('troca a contagem de estoque por "sem estoque" quando ele zera', () => {
    expect(montar().find('[data-testid="selo-estoque"]').text()).toContain(
      '12'
    );
    expect(
      montar({ stock: 0 }).find('[data-testid="selo-estoque"]').text()
    ).toBe('Out of stock');
  });

  it('omite o selo de estoque quando o produto não controla estoque', () => {
    expect(
      montar({ stock: null }).find('[data-testid="selo-estoque"]').exists()
    ).toBe(false);
  });

  // O estado vem pronto do backend; o card só o pinta.
  it('mostra o estado do espelho que o backend calculou', () => {
    const selo = extra =>
      montar(extra, { metaSyncEnabled: true }).find(
        '[data-testid="selo-meta"]'
      );

    expect(selo({ meta_status: 'sincronizado' }).text()).toBe('On Meta');
    expect(selo({ meta_status: 'pendente' }).text()).toBe('Meta pending');
    expect(
      selo({ meta_status: 'incompleto', meta_missing: ['foto'] }).text()
    ).toBe('Incomplete');
    // Oculto não tem estado: o selo "Oculto" já diz tudo.
    expect(selo({ meta_status: null }).exists()).toBe(false);
  });

  it('esconde o selo quando a conta não tem espelho configurado', () => {
    expect(
      montar({ meta_status: 'pendente' })
        .find('[data-testid="selo-meta"]')
        .exists()
    ).toBe(false);
  });

  it('abre o cadastro ao clicar no card', async () => {
    const wrapper = montar();

    await wrapper.find('[data-testid="abrir-produto"]').trigger('click');

    expect(wrapper.emitted('abrir')[0][0]).toMatchObject({ id: 1 });
  });
});
