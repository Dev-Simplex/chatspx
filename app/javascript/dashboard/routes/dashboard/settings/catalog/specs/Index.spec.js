import { mount, flushPromises } from '@vue/test-utils';
import CatalogIndex from '../Index.vue';

const { listarProdutos, listarCategorias } = vi.hoisted(() => ({
  listarProdutos: vi.fn(),
  listarCategorias: vi.fn(),
}));

vi.mock('dashboard/api/catalog', () => ({
  CatalogProducts: { listar: listarProdutos },
  CatalogCategories: { get: listarCategorias },
}));

// A rota do cadastro é a C7 e ainda não existe — `hasRoute` respondendo `false` é exatamente o
// estado que a tela precisa aguentar sem derrubar o router.
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ hasRoute: () => false, push: vi.fn() }),
}));

// lottie-web cria um canvas no import e o jsdom nao o implementa — ele entra no grafo de
// modulos de forma transitiva (mesmo truque do spec de Times).
vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));

const produtos = [
  {
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
  },
  {
    id: 2,
    name: 'Oakley Holbrook Prizm',
    sku: 'OO9102-B7',
    price_cents: 89900,
    promo_price_cents: null,
    current_price_cents: 89900,
    on_sale: false,
    currency: 'BRL',
    stock: 0,
    visible: false,
    featured: false,
    cover_url: null,
  },
];

const categorias = [
  { id: 7, name: 'Óculos de sol', products_count: 2 },
  { id: 8, name: 'Armação de grau', products_count: 0 },
];

const resposta = (payload = produtos, total = payload.length) => ({
  data: { payload, meta: { total, page: 1, per_page: 25 } },
});

const SettingsLayoutStub = {
  name: 'SettingsLayout',
  props: ['isLoading', 'loadingMessage', 'noRecordsFound', 'noRecordsMessage'],
  template: `<div>
      <slot name="header" />
      <slot name="preBody" />
      <span v-if="isLoading" class="carregando">{{ loadingMessage }}</span>
      <span v-else-if="noRecordsFound" class="vazio">{{ noRecordsMessage }}</span>
      <slot v-else name="body" />
    </div>`,
};

const BaseSettingsHeaderStub = {
  name: 'BaseSettingsHeader',
  props: ['title', 'description', 'searchPlaceholder', 'searchQuery'],
  emits: ['update:searchQuery'],
  template: `<div class="cabecalho">
      <input
        class="busca"
        :value="searchQuery"
        @input="$emit('update:searchQuery', $event.target.value)"
      />
      <slot name="count" />
      <slot name="actions" />
    </div>`,
};

const ButtonStub = {
  name: 'Button',
  props: ['label', 'size'],
  template: '<button>{{ label }}</button>',
};

const SelectStub = {
  name: 'Select',
  props: ['options', 'modelValue'],
  emits: ['update:modelValue'],
  template: `<select
      class="categoria"
      :value="modelValue"
      @change="$emit('update:modelValue', $event.target.value)"
    >
      <option v-for="opcao in options" :key="opcao.value" :value="opcao.value">
        {{ opcao.label }}
      </option>
    </select>`,
};

const CheckboxStub = {
  name: 'Checkbox',
  props: ['modelValue'],
  emits: ['update:modelValue'],
  template: `<input
      class="so-visiveis"
      type="checkbox"
      :checked="modelValue"
      @change="$emit('update:modelValue', $event.target.checked)"
    />`,
};

const PaginationFooterStub = {
  name: 'PaginationFooter',
  props: ['currentPage', 'totalItems', 'itemsPerPage'],
  template: '<div class="paginacao">{{ currentPage }}</div>',
};

const montar = () =>
  mount(CatalogIndex, {
    global: {
      stubs: {
        SettingsLayout: SettingsLayoutStub,
        BaseSettingsHeader: BaseSettingsHeaderStub,
        Button: ButtonStub,
        Select: SelectStub,
        Checkbox: CheckboxStub,
        PaginationFooter: PaginationFooterStub,
      },
    },
  });

const ultimaChamada = () =>
  listarProdutos.mock.calls[listarProdutos.mock.calls.length - 1][0];

describe('Catálogo · Index', () => {
  beforeEach(() => {
    listarProdutos.mockResolvedValue(resposta());
    listarCategorias.mockResolvedValue({ data: categorias });
  });

  it('mostra na grade os produtos que a resposta trouxe', async () => {
    const wrapper = montar();
    await flushPromises();

    const cards = wrapper.findAll('[data-testid="abrir-produto"]');
    expect(cards).toHaveLength(2);
    expect(wrapper.text()).toContain('Ray-Ban Aviador Clássico');
    expect(wrapper.text()).toContain('Oakley Holbrook Prizm');
    expect(wrapper.text()).toContain('RB3025-001');
  });

  it('manda a busca para a API em `q`, e não peneira a lista em memória', async () => {
    vi.useFakeTimers();
    try {
      const wrapper = montar();
      await flushPromises();

      await wrapper.find('input.busca').setValue('oakley');
      await vi.advanceTimersByTimeAsync(400);
      await flushPromises();

      expect(ultimaChamada()).toMatchObject({ q: 'oakley', page: 1 });
    } finally {
      vi.useRealTimers();
    }
  });

  it('manda a categoria escolhida em `category_id`', async () => {
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('select.categoria').setValue('7');
    await flushPromises();

    expect(ultimaChamada()).toMatchObject({ categoryId: '7', page: 1 });
  });

  it('manda `visible_only` quando o filtro de visíveis está marcado', async () => {
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('input.so-visiveis').setValue(true);
    await flushPromises();

    expect(ultimaChamada()).toMatchObject({ visibleOnly: true, page: 1 });
  });

  it('avisa que não há produto quando a lista volta vazia', async () => {
    listarProdutos.mockResolvedValue(resposta([], 0));

    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('.vazio').exists()).toBe(true);
    expect(wrapper.find('[data-testid="catalogo-grade"]').exists()).toBe(false);
  });

  it('mostra alerta quando a API falha, em vez de uma tela vazia sem explicação', async () => {
    listarProdutos.mockRejectedValue(new Error('500'));

    const wrapper = montar();
    await flushPromises();

    const alerta = wrapper.find('[data-testid="catalogo-erro"]');
    expect(alerta.exists()).toBe(true);
    expect(alerta.text()).not.toBe('');
    expect(wrapper.find('.vazio').exists()).toBe(false);
  });
});
