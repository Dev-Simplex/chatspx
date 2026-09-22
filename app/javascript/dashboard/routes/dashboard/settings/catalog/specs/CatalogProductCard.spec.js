import { mount } from '@vue/test-utils';
import CatalogProductCard from '../CatalogProductCard.vue';

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

  // O selo responde ao `meta_product_id`, que é a prova de que o espelho existe lá; o
  // `meta_synced_at` diz só quando foi conferido e por isso vai no tooltip.
  it('mostra o selo da Meta só quando o produto tem espelho lá', () => {
    expect(montar().find('[data-testid="selo-meta"]').exists()).toBe(false);
    expect(
      montar({ meta_product_id: 'meta_123' })
        .find('[data-testid="selo-meta"]')
        .exists()
    ).toBe(true);
  });

  it('esconde "Enviar no chat" enquanto a C8 não liga o envio', () => {
    expect(montar().find('[data-testid="enviar-no-chat"]').exists()).toBe(
      false
    );
  });

  it('emite `sendToChat` com o produto quando o envio está liberado', async () => {
    const wrapper = montar({}, { canSend: true });

    await wrapper.find('[data-testid="enviar-no-chat"]').trigger('click');

    expect(wrapper.emitted('sendToChat')[0][0]).toMatchObject({ id: 1 });
  });

  it('abre o cadastro ao clicar no card', async () => {
    const wrapper = montar();

    await wrapper.find('[data-testid="abrir-produto"]').trigger('click');

    expect(wrapper.emitted('abrir')[0][0]).toMatchObject({ id: 1 });
  });
});
