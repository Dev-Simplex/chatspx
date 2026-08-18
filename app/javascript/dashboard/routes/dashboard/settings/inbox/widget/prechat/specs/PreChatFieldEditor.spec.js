import { config, mount } from '@vue/test-utils';
import PreChatFieldEditor from '../PreChatFieldEditor.vue';

const [i18n] = config.global.plugins;
const withLocale = locale => {
  i18n.global.locale.value = locale;
};

afterEach(() => withLocale('en'));

const baseField = (extra = {}) => ({
  name: 'cpf',
  label: 'CPF',
  placeholder: 'Digite seu CPF',
  field_type: 'contact_attribute',
  type: 'text',
  enabled: true,
  required: false,
  ...extra,
});

const build = (field = {}, props = {}, locale = 'pt_BR') => {
  withLocale(locale);
  return mount(PreChatFieldEditor, {
    props: { field: baseField(field), sources: [], ...props },
  });
};

const preview = wrapper => wrapper.find('[data-testid="field-preview"]');
const previewInput = wrapper => preview(wrapper).find('input');
const message = wrapper => preview(wrapper).find('p');

describe('PreChatFieldEditor — validação no blur (aceite 26)', () => {
  it('não mostra erro nenhum enquanto se digita, tecla a tecla', async () => {
    const wrapper = build({ validator: 'cpf' });
    const input = previewInput(wrapper);

    // Sete teclas de um CPF inválido: em nenhuma delas pode haver mensagem.
    await ['5', '52', '529', '5299', '52998', '529982', '5299822'].reduce(
      async (previous, partial) => {
        await previous;
        await input.setValue(partial);
        expect(message(wrapper).exists()).toBe(false);
      },
      Promise.resolve()
    );
  });

  it('mostra o erro só quando o campo perde o foco', async () => {
    const wrapper = build({ validator: 'cpf' });
    const input = previewInput(wrapper);

    await input.setValue('111.111.111-11');
    expect(message(wrapper).exists()).toBe(false);

    await input.trigger('blur');
    expect(message(wrapper).text()).toBe(
      'Confira o CPF: os números não fecham.'
    );
  });

  it('some com a mensagem quando o valor passa a valer', async () => {
    const wrapper = build({ validator: 'cpf' });
    const input = previewInput(wrapper);

    await input.setValue('111.111.111-11');
    await input.trigger('blur');
    expect(message(wrapper).exists()).toBe(true);

    await input.setValue('529.982.247-25');
    expect(message(wrapper).exists()).toBe(false);
  });
});

describe('PreChatFieldEditor — máscara e mensagem', () => {
  it('aplica a máscara do campo no que é digitado', async () => {
    const wrapper = build({ mask: 'cpf' });

    await previewInput(wrapper).setValue('52998224725');

    expect(previewInput(wrapper).element.value).toBe('529.982.247-25');
  });

  it('a mensagem de erro própria do cliente ganha do texto padrão', async () => {
    const wrapper = build({
      validator: 'cpf',
      error_message: 'Esse CPF não confere com o do seu pedido',
    });

    await previewInput(wrapper).setValue('111.111.111-11');
    await previewInput(wrapper).trigger('blur');

    expect(message(wrapper).text()).toBe(
      'Esse CPF não confere com o do seu pedido'
    );
  });

  it('anti-lixo é aviso, não erro — a mensagem não vem em vermelho', async () => {
    const wrapper = build({ validator: 'junk_name', name: 'fullName' });

    await previewInput(wrapper).setValue('aaaa');
    await previewInput(wrapper).trigger('blur');

    expect(message(wrapper).text()).toBe(
      'Esse nome parece incompleto. Confere?'
    );
    expect(message(wrapper).classes().join(' ')).not.toContain('ruby');
  });

  it('validação dura vem em vermelho', async () => {
    const wrapper = build({ validator: 'cpf' });

    await previewInput(wrapper).setValue('111.111.111-11');
    await previewInput(wrapper).trigger('blur');

    expect(message(wrapper).classes().join(' ')).toContain('ruby');
  });

  it('o mesmo campo em en traz a mensagem em en', async () => {
    const wrapper = build({ validator: 'corporate_email' }, {}, 'en');

    await previewInput(wrapper).setValue('fulano@gmail.com');
    await previewInput(wrapper).trigger('blur');

    expect(message(wrapper).text()).toBe(
      'Use your work email, not a free provider.'
    );
  });
});

describe('PreChatFieldEditor — o que ele avisa quem consome', () => {
  it('emite a alteração de rótulo sem tocar no campo recebido', async () => {
    const field = baseField();
    const wrapper = mount(PreChatFieldEditor, {
      props: { field, sources: [] },
    });

    await wrapper
      .find('[data-testid="field-label"]')
      .find('input')
      .setValue('Seu CPF');

    expect(wrapper.emitted('update').at(-1)).toEqual([{ label: 'Seu CPF' }]);
    expect(field.label).toBe('CPF');
  });

  it('cobra o rótulo vazio no blur, e não antes', async () => {
    const wrapper = build({ label: '' });
    const labelInput = wrapper
      .find('[data-testid="field-label"]')
      .find('input');

    expect(wrapper.find('[data-testid="field-label"]').find('p').exists()).toBe(
      false
    );

    await labelInput.trigger('blur');

    expect(wrapper.find('[data-testid="field-label"]').find('p').text()).toBe(
      'O rótulo é o que o visitante lê. Sem ele, o campo aparece com o nome interno.'
    );
  });

  it('avisa que o tipo do campo padrão é travado', () => {
    const wrapper = build({ field_type: 'standard' });

    expect(wrapper.text()).toContain(
      'Campo padrão: o tipo não muda, porque ele alimenta o cadastro do contato.'
    );
  });

  it('campo personalizado não recebe o aviso de tipo travado', () => {
    const wrapper = build();

    expect(wrapper.text()).not.toContain('Campo padrão:');
  });
});
