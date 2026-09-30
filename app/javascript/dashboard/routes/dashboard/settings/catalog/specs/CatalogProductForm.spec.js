import { mount, flushPromises } from '@vue/test-utils';
import CatalogProductForm from '../CatalogProductForm.vue';

const {
  mostrarProduto,
  criarProduto,
  atualizarProduto,
  removerImagem,
  listarCategorias,
  sincronizarProduto,
  alertar,
  empurrar,
  parametros,
} = vi.hoisted(() => ({
  sincronizarProduto: vi.fn(),
  alertar: vi.fn(),
  mostrarProduto: vi.fn(),
  criarProduto: vi.fn(),
  atualizarProduto: vi.fn(),
  removerImagem: vi.fn(),
  listarCategorias: vi.fn(),
  empurrar: vi.fn(),
  parametros: { accountId: '1', productId: 'new' },
}));

vi.mock('dashboard/api/catalog', () => ({
  CatalogProducts: {
    show: mostrarProduto,
    create: criarProduto,
    update: atualizarProduto,
    removerImagem,
    sincronizarProduto,
  },
  CatalogCategories: { get: listarCategorias },
}));

vi.mock('dashboard/composables', () => ({ useAlert: alertar }));

vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ params: parametros }),
  useRouter: () => ({ push: empurrar }),
}));

// lottie-web cria um canvas no import e o jsdom nao o implementa — ele entra no grafo de
// modulos de forma transitiva (mesmo truque do spec da grade).
vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));

const produto = {
  id: 7,
  name: 'Ray-Ban Aviador Clássico',
  description: 'Armação metálica dourada',
  price_cents: 74900,
  promo_price_cents: 62900,
  current_price_cents: 62900,
  on_sale: true,
  currency: 'BRL',
  sku: 'RB3025-001',
  stock: 12,
  visible: true,
  featured: false,
  catalog_category_id: 7,
  category_name: 'Óculos de sol',
  meta_product_id: '8841203',
  meta_synced_at: '2026-09-22T09:41:00.000Z',
  meta_status: 'sincronizado',
  meta_missing: [],
  meta_sync_enabled: true,
  images: [{ id: 55, url: 'https://exemplo.test/rb.jpg', filename: 'rb.jpg' }],
  cover_url: 'https://exemplo.test/rb.jpg',
};

const categorias = [
  { id: 7, name: 'Óculos de sol', products_count: 2 },
  { id: 8, name: 'Armação de grau', products_count: 0 },
];

const SettingsLayoutStub = {
  name: 'SettingsLayout',
  props: ['isLoading', 'loadingMessage'],
  template: `<div>
      <slot name="header" />
      <slot name="preBody" />
      <span v-if="isLoading" class="carregando">{{ loadingMessage }}</span>
      <slot v-else name="body" />
    </div>`,
};

const BaseSettingsHeaderStub = {
  name: 'BaseSettingsHeader',
  props: ['title', 'backButtonLabel'],
  template: `<div class="cabecalho">
      <h1 class="titulo">{{ title }}</h1>
      <slot name="count" />
      <slot name="actions" />
    </div>`,
};

const ButtonStub = {
  name: 'Button',
  props: ['label', 'isLoading', 'size'],
  template: '<button>{{ label }}</button>',
};

const InputStub = {
  name: 'Input',
  props: [
    'modelValue',
    'label',
    'message',
    'messageType',
    'type',
    'min',
    'placeholder',
  ],
  emits: ['update:modelValue'],
  template: `<span>
      <input :value="modelValue" @input="$emit('update:modelValue', $event.target.value)" />
      <em>{{ message }}</em>
    </span>`,
};

const TextAreaStub = {
  name: 'TextArea',
  props: ['modelValue', 'label', 'maxLength', 'autoHeight'],
  emits: ['update:modelValue'],
  template: `<span>
      <textarea :value="modelValue" @input="$emit('update:modelValue', $event.target.value)" />
    </span>`,
};

const SelectStub = {
  name: 'Select',
  props: ['options', 'modelValue'],
  emits: ['update:modelValue'],
  template: `<select :value="modelValue" @change="$emit('update:modelValue', $event.target.value)">
      <option v-for="opcao in options" :key="opcao.value" :value="opcao.value">
        {{ opcao.label }}
      </option>
    </select>`,
};

const SwitchStub = {
  name: 'Switch',
  props: ['modelValue'],
  emits: ['update:modelValue'],
  template: `<button
      :aria-checked="String(modelValue)"
      @click="$emit('update:modelValue', !modelValue)"
    />`,
};

const montar = () =>
  mount(CatalogProductForm, {
    global: {
      stubs: {
        SettingsLayout: SettingsLayoutStub,
        BaseSettingsHeader: BaseSettingsHeaderStub,
        Button: ButtonStub,
        Input: InputStub,
        TextArea: TextAreaStub,
        Select: SelectStub,
        Switch: SwitchStub,
      },
    },
  });

const campo = (wrapper, testid) =>
  wrapper.find(`[data-testid="${testid}"] input`);

const corpoEnviado = chamada => chamada[chamada.length - 1];

describe('Catálogo · formulário do produto', () => {
  beforeEach(() => {
    parametros.productId = 'new';
    listarCategorias.mockResolvedValue({ data: categorias });
    mostrarProduto.mockResolvedValue({ data: produto });
    criarProduto.mockResolvedValue({ data: { ...produto, id: 9 } });
    atualizarProduto.mockResolvedValue({ data: produto });
    removerImagem.mockResolvedValue({ data: { ...produto, images: [] } });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('abre em branco quando o id da rota é `new`', async () => {
    const wrapper = montar();
    await flushPromises();

    expect(mostrarProduto).not.toHaveBeenCalled();
    expect(wrapper.find('h1.titulo').text()).toBe('New product');
    expect(campo(wrapper, 'campo-nome').element.value).toBe('');
  });

  it('carrega o produto quando a rota traz um id', async () => {
    parametros.productId = '7';
    const wrapper = montar();
    await flushPromises();

    expect(mostrarProduto).toHaveBeenCalledWith('7');
    expect(wrapper.find('h1.titulo').text()).toBe('Ray-Ban Aviador Clássico');
    // O campo mostra REAIS mesmo com a API falando em centavos.
    expect(campo(wrapper, 'campo-preco').element.value).toBe('749,00');
    expect(campo(wrapper, 'campo-sku').element.value).toBe('RB3025-001');
  });

  it('cria por POST, com o preço convertido para centavos', async () => {
    const wrapper = montar();
    await flushPromises();

    await campo(wrapper, 'campo-nome').setValue('Oakley Holbrook');
    await campo(wrapper, 'campo-preco').setValue('1.299,90');
    await campo(wrapper, 'campo-preco-promocional').setValue('999,00');
    await wrapper.find('[data-testid="salvar-produto"]').trigger('click');
    await flushPromises();

    expect(atualizarProduto).not.toHaveBeenCalled();
    const corpo = corpoEnviado(criarProduto.mock.calls[0]);
    expect(corpo.get('catalog_product[name]')).toBe('Oakley Holbrook');
    expect(corpo.get('catalog_product[price_cents]')).toBe('129990');
    expect(corpo.get('catalog_product[promo_price_cents]')).toBe('99900');
    expect(empurrar).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'catalog_products_index' })
    );
  });

  it('edita por PATCH no id da rota', async () => {
    parametros.productId = '7';
    const wrapper = montar();
    await flushPromises();

    await campo(wrapper, 'campo-preco').setValue('699,00');
    await wrapper.find('[data-testid="salvar-produto"]').trigger('click');
    await flushPromises();

    expect(criarProduto).not.toHaveBeenCalled();
    expect(atualizarProduto).toHaveBeenCalledTimes(1);
    const [id, corpo] = atualizarProduto.mock.calls[0];
    expect(id).toBe('7');
    expect(corpo.get('catalog_product[price_cents]')).toBe('69900');
  });

  it('não salva sem nome, e diz por quê', async () => {
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-testid="salvar-produto"]').trigger('click');
    await flushPromises();

    expect(criarProduto).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('Give the product a name.');
  });

  it('remove foto já salva pelo endpoint de imagem', async () => {
    parametros.productId = '7';
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-testid="remover-foto"]').trigger('click');
    await flushPromises();

    expect(removerImagem).toHaveBeenCalledWith('7', 55);
    expect(wrapper.find('[data-testid="remover-foto"]').exists()).toBe(false);
  });

  it('mostra o estado do espelho e o id do item na Meta', async () => {
    parametros.productId = '7';
    const wrapper = montar();
    await flushPromises();

    const painel = wrapper.find('[data-testid="painel-sincronizacao"]');
    expect(painel.text()).toContain('On Meta');
    expect(painel.text()).toContain('8841203');
  });

  it('esconde o painel quando a conta não tem espelho configurado', async () => {
    parametros.productId = '7';
    mostrarProduto.mockResolvedValue({
      data: { ...produto, meta_sync_enabled: false },
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-testid="painel-sincronizacao"]').exists()).toBe(
      false
    );
  });

  it('não oferece sincronizar produto incompleto', async () => {
    parametros.productId = '7';
    mostrarProduto.mockResolvedValue({
      data: { ...produto, meta_status: 'incompleto', meta_missing: ['sku'] },
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-testid="sincronizar-produto"]').exists()).toBe(
      false
    );
  });

  it('enfileira a sincronização do produto e o mostra pendente', async () => {
    parametros.productId = '7';
    sincronizarProduto.mockResolvedValue({
      data: { ...produto, meta_status: 'pendente', meta_synced_at: null },
    });
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-testid="sincronizar-produto"]').trigger('click');
    await flushPromises();

    expect(sincronizarProduto).toHaveBeenCalledWith('7');
    expect(alertar).toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="painel-sincronizacao"]').text()
    ).toContain('Meta pending');
  });

  it('mostra o erro que a API devolveu, sem apagar o que foi digitado', async () => {
    criarProduto.mockRejectedValue({
      response: { data: { message: 'Sku já está em uso' } },
    });
    const wrapper = montar();
    await flushPromises();

    await campo(wrapper, 'campo-nome').setValue('Oakley Holbrook');
    await campo(wrapper, 'campo-sku').setValue('RB3025-001');
    await wrapper.find('[data-testid="salvar-produto"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="erro-do-formulario"]').text()).toContain(
      'Sku já está em uso'
    );
    expect(empurrar).not.toHaveBeenCalled();
    expect(campo(wrapper, 'campo-nome').element.value).toBe('Oakley Holbrook');
  });
});
