import { config, mount } from '@vue/test-utils';
import Widget from '../components/Widget.vue';
import WidgetPreChatPreview from '../components/WidgetPreChatPreview.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { logoThumbnail: '/logo.png' } }),
  useStore: () => ({ getters: {}, dispatch: vi.fn() }),
}));

const [i18n] = config.global.plugins;
const withLocale = locale => {
  i18n.global.locale.value = locale;
};

afterEach(() => withLocale('en'));

const field = (name, extra = {}) => ({
  name,
  label: name,
  field_type: 'standard',
  type: 'text',
  enabled: true,
  required: false,
  ...extra,
});

const options = (fields, extra = {}) => ({
  pre_chat_message: 'Antes de começar, conte quem é você',
  pre_chat_fields: fields,
  ...extra,
});

const buildPreview = (opts, locale = 'pt_BR') => {
  withLocale(locale);
  return mount(WidgetPreChatPreview, { props: { options: opts } });
};

const buildWidget = (props = {}) => {
  withLocale('pt_BR');
  return mount(Widget, {
    props: { websiteName: 'Simplex', color: '#2dc46f', ...props },
    global: { stubs: { Code: true, TabBar: true } },
  });
};

const fieldNodes = wrapper =>
  wrapper.findAll('[data-testid="prechat-preview-field"]');

describe('3.16 — a etapa 1 no preview mostra o que a tela configurou', () => {
  it('mostra a mensagem e só os campos habilitados, na ordem configurada', () => {
    const wrapper = buildPreview(
      options([
        field('phoneNumber', { label: 'Telefone', position: 1 }),
        field('fullName', { label: 'Nome', position: 0 }),
        field('emailAddress', { label: 'E-mail', enabled: false }),
      ])
    );

    expect(wrapper.text()).toContain('Antes de começar, conte quem é você');
    // O primeiro <span> de cada campo é o rótulo; o resto é placeholder e ajuda.
    expect(fieldNodes(wrapper).map(node => node.find('span').text())).toEqual([
      'Nome',
      'Telefone',
    ]);
  });

  it('mostra SÓ a etapa 1, e diz quantas etapas existem', () => {
    const wrapper = buildPreview(
      options([
        field('fullName', { label: 'Nome', step: 1 }),
        field('emailAddress', { label: 'E-mail', step: 2 }),
        field('phoneNumber', { label: 'Telefone', step: 3 }),
      ])
    );

    expect(fieldNodes(wrapper)).toHaveLength(1);
    expect(wrapper.find('[data-testid="prechat-preview-steps"]').text()).toBe(
      'Etapa 1 de 3 — as seguintes aparecem depois que esta for respondida.'
    );
  });

  it('formulário de uma etapa não fala em etapa nenhuma', () => {
    const wrapper = buildPreview(options([field('fullName')]));

    expect(wrapper.find('[data-testid="prechat-preview-steps"]').exists()).toBe(
      false
    );
  });

  it('o obrigatório aparece marcado, e o opcional não', () => {
    const wrapper = buildPreview(
      options([
        field('fullName', { label: 'Nome', required: true, position: 0 }),
        field('phoneNumber', { label: 'Telefone', position: 1 }),
      ])
    );

    const [required, optional] = fieldNodes(wrapper);
    expect(
      required.find('[data-testid="prechat-preview-required"]').text()
    ).toBe('*');
    expect(
      optional.find('[data-testid="prechat-preview-required"]').exists()
    ).toBe(false);
  });

  it('o texto de ajuda configurado aparece embaixo do campo', () => {
    const wrapper = buildPreview(
      options([
        field('cpf', {
          label: 'CPF',
          help_text: 'Usamos para achar seu pedido',
        }),
      ])
    );

    expect(wrapper.find('[data-testid="prechat-preview-help"]').text()).toBe(
      'Usamos para achar seu pedido'
    );
  });

  it('o placeholder é o configurado; campo padrão sem rótulo cai no texto traduzido', () => {
    const wrapper = buildPreview(
      options([
        field('emailAddress', {
          label: '',
          placeholder: '',
          type: 'email',
        }),
      ])
    );

    const node = fieldNodes(wrapper)[0];
    expect(node.text()).toContain('Endereço de e-mail');
    expect(node.text()).toContain('Por favor, digite seu e-mail');
    // o nome interno NUNCA chega ao visitante
    expect(node.text()).not.toContain('emailAddress');
  });

  it('sem campo habilitado, diz que o visitante vai direto para a conversa', () => {
    const wrapper = buildPreview(
      options([field('fullName', { enabled: false })])
    );

    expect(wrapper.find('[data-testid="prechat-preview-empty"]').text()).toBe(
      'Nenhum campo ligado: o visitante vai direto para a conversa.'
    );
    expect(fieldNodes(wrapper)).toHaveLength(0);
  });

  it('o botão usa os tokens da marca, nunca uma cor crua', () => {
    const wrapper = buildPreview(options([field('fullName')]));
    const button = wrapper.find('[data-testid="prechat-preview-submit"]');

    expect(button.classes()).toContain('bg-w-brand');
    expect(button.classes()).toContain('text-w-on-brand');
    expect(button.attributes('style')).toBeUndefined();
  });

  it('em en o preview também sai traduzido', () => {
    const wrapper = buildPreview(options([field('fullName')]), 'en');

    expect(wrapper.find('[data-testid="prechat-preview-submit"]').text()).toBe(
      'Start conversation'
    );
  });
});

describe('3.16 — o preview inteiro, com e sem pré-chat', () => {
  const withChatMode = async wrapper => {
    // O primeiro Switch do preview é o "Chat": sem ele, a tela mostrada é a
    // inicial, e nem pré-chat nem bolhas aparecem.
    await wrapper.findAll('button[role="switch"]')[0].trigger('click');
  };

  it('com o pré-chat ligado, a conversa começa pelo formulário', async () => {
    const wrapper = buildWidget({
      preChatEnabled: true,
      preChatOptions: options([field('fullName', { label: 'Nome' })]),
    });

    await withChatMode(wrapper);

    expect(wrapper.find('[data-testid="prechat-preview"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Nome');
  });

  it('com o pré-chat desligado, o preview mostra as bolhas de sempre', async () => {
    const wrapper = buildWidget({
      preChatEnabled: false,
      preChatOptions: options([field('fullName', { label: 'Nome' })]),
    });

    await withChatMode(wrapper);

    expect(wrapper.find('[data-testid="prechat-preview"]').exists()).toBe(
      false
    );
  });

  it('sem nenhuma prop de pré-chat, o preview continua como era', async () => {
    const wrapper = buildWidget();

    await withChatMode(wrapper);

    expect(wrapper.find('[data-testid="prechat-preview"]').exists()).toBe(
      false
    );
  });
});
