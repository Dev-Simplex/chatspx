import { config, mount } from '@vue/test-utils';
import PreChatStepList from '../PreChatStepList.vue';

const [i18n] = config.global.plugins;
const withLocale = locale => {
  i18n.global.locale.value = locale;
};

afterEach(() => withLocale('en'));

const field = (name, extra = {}) => ({
  name,
  label: name,
  field_type: 'contact_attribute',
  type: 'text',
  enabled: true,
  required: false,
  ...extra,
});

const build = (fields, props = {}, locale = 'pt_BR') => {
  withLocale(locale);
  return mount(PreChatStepList, { props: { fields, ...props } });
};

const counter = wrapper => wrapper.find('[data-testid="field-counter"]');
const limitReason = wrapper =>
  wrapper.find('[data-testid="field-limit-reason"]');

describe('PreChatStepList — o teto de 8 (aceite 21)', () => {
  it('mostra o contador com o número real de campos habilitados', () => {
    const fields = [
      field('a'),
      field('b'),
      field('c'),
      field('d', { enabled: false }),
    ];

    expect(counter(build(fields)).text()).toBe('3 de 8 campos');
  });

  it('com 8 habilitados o contador vira 8 de 8 e o motivo aparece na tela', () => {
    const fields = [
      ...Array.from({ length: 8 }, (_, i) => field(`f${i}`)),
      field('sobra', { enabled: false }),
    ];
    const wrapper = build(fields);

    expect(counter(wrapper).text()).toBe('8 de 8 campos');
    expect(limitReason(wrapper).text()).toBe(
      'Você chegou ao limite de 8 campos. Formulário longo é a principal causa de abandono — para adicionar outro, remova um dos que já estão aqui.'
    );
  });

  it('no teto, o seletor de adicionar some e sobra o botão desabilitado', () => {
    const fields = [
      ...Array.from({ length: 8 }, (_, i) => field(`f${i}`)),
      field('sobra', { enabled: false }),
    ];
    const wrapper = build(fields);

    expect(wrapper.find('[data-testid="add-field-step-1"]').exists()).toBe(
      false
    );
    const disabled = wrapper.find('[data-testid="add-field-disabled-1"]');
    expect(disabled.exists()).toBe(true);
    expect(disabled.attributes('disabled')).toBeDefined();
  });

  it('com 7 habilitados ainda dá para adicionar, e o motivo não aparece', () => {
    const fields = [
      ...Array.from({ length: 7 }, (_, i) => field(`f${i}`)),
      field('sobra', { enabled: false }),
    ];
    const wrapper = build(fields);

    expect(counter(wrapper).text()).toBe('7 de 8 campos');
    expect(limitReason(wrapper).exists()).toBe(false);
    expect(wrapper.find('[data-testid="add-field-step-1"]').exists()).toBe(
      true
    );
  });

  it('o contador conta campo habilitado, não entrada do array', () => {
    // O formato da frota: 3 ligados e 9 atributos personalizados desligados.
    const fields = [
      field('a'),
      field('b'),
      field('c'),
      ...Array.from({ length: 9 }, (_, i) =>
        field(`attr_${i}`, { enabled: false })
      ),
    ];
    const wrapper = build(fields);

    expect(fields).toHaveLength(12);
    expect(counter(wrapper).text()).toBe('3 de 8 campos');
    expect(limitReason(wrapper).exists()).toBe(false);
  });

  it('em en o contador e o motivo também saem traduzidos', () => {
    const fields = Array.from({ length: 8 }, (_, i) => field(`f${i}`));
    const wrapper = build(fields, {}, 'en');

    expect(counter(wrapper).text()).toBe('8 of 8 fields');
    expect(limitReason(wrapper).text()).toContain('limit of 8 fields');
  });
});

describe('PreChatStepList — etapas', () => {
  it('no modo Simples não mostra título de etapa nem o botão de nova etapa', () => {
    const wrapper = build([field('a'), field('b', { step: 2 })], {
      showSteps: false,
    });

    expect(wrapper.find('[data-testid="add-step"]').exists()).toBe(false);
    expect(wrapper.findAll('[data-testid="step-section"]')).toHaveLength(1);
  });

  it('no Construtor mostra uma seção por etapa, com o título numerado', () => {
    const wrapper = build([
      field('a', { step: 1 }),
      field('b', { step: 2 }),
      field('c', { step: 3 }),
    ]);

    const sections = wrapper.findAll('[data-testid="step-section"]');
    expect(sections).toHaveLength(3);
    expect(sections[1].text()).toContain('Etapa 2');
  });

  it('etapa vazia diz que ela não será mostrada ao visitante', () => {
    const wrapper = build([field('a', { step: 1 }), field('c', { step: 3 })]);

    expect(wrapper.find('[data-testid="empty-step"]').text()).toBe(
      'Esta etapa ainda não tem campo. Adicione um abaixo ou ela não será mostrada ao visitante.'
    );
  });

  it('no teto de 8 etapas o botão de nova etapa desabilita', () => {
    const fields = Array.from({ length: 8 }, (_, i) =>
      field(`f${i}`, { step: i + 1 })
    );
    const wrapper = build([...fields, field('sobra', { enabled: false })]);

    expect(
      wrapper.find('[data-testid="add-step"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.find('[data-testid="step-counter"]').text()).toBe(
      '8 de 8 etapas'
    );
  });
});

describe('PreChatStepList — o que ele avisa quem consome', () => {
  it('habilitar um campo devolve a lista com ele ligado na etapa pedida', async () => {
    const fields = [field('a'), field('novo', { enabled: false })];
    const wrapper = build(fields);

    await wrapper
      .find('[data-testid="add-field-step-1"]')
      .find('select')
      .setValue('novo');

    const emitted = wrapper.emitted('update:fields').at(-1)[0];
    const added = emitted.find(f => f.name === 'novo');
    expect(added.enabled).toBe(true);
    expect(added.step).toBe(1);
  });

  it('nomeia a condicional órfã em vez de escondê-la', () => {
    const fields = [
      field('nome', { step: 1, enabled: false }),
      field('cpf', { step: 2, show_if: { field: 'nome', operator: 'filled' } }),
    ];
    const wrapper = build(fields);

    expect(
      wrapper.find('[data-testid="dangling-conditions"]').text()
    ).toContain('cpf');
  });
});
