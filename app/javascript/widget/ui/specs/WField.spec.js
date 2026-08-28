import { mount } from '@vue/test-utils';
import { plugin, defaultConfig } from '@formkit/vue';
import WField from '../WField.vue';
import WScrollToBottom from '../WScrollToBottom.vue';
import WTeaserCard from '../WTeaserCard.vue';
import WComposer from '../WComposer.vue';
import WIconButton from '../WIconButton.vue';

/**
 * WField é o destino da delegação do bloco 3.15: um campo do pré-chat, com o
 * tipo, as opções, as regras e as mensagens que antes moravam dentro de
 * `PreChat/Form.vue`.
 *
 * O FormKit é montado DE VERDADE aqui, sem dublê. É a única forma de medir as
 * duas coisas que este componente promete e que um stub responderia sozinho: o
 * `<label for>` apontando para o `id` do controle, e a FORMA do controle que
 * cada tipo do painel produz — inclusive o `<select>` indexado por posição, que
 * é a premissa do defeito que o 3.15 fecha.
 */
const campo = (extra = {}) => ({
  name: 'tipo',
  label: 'Tipo',
  type: 'text',
  enabled: true,
  required: false,
  ...extra,
});

describe('WField', () => {
  const montar = (field = campo(), props = {}) =>
    mount(WField, {
      props: { field, label: field.label, ...props },
      global: {
        plugins: [[plugin, defaultConfig()]],
        mocks: { $t: key => key },
      },
    });

  it('o rótulo aponta para o campo de verdade (for === id)', () => {
    // É esta ligação que separa "rótulo" de "texto solto ao lado". A violação
    // `label` medida pelo axe nos tipos ricos é exatamente a falta dela.
    const el = montar();
    const id = el.find('input').attributes('id');

    expect(id).toBeTruthy();
    expect(el.find('label').attributes('for')).toBe(id);
    expect(el.find('label').text()).toContain('Tipo');
  });

  it('dois campos na mesma tela não colidem de id', () => {
    const a = montar(campo({ name: 'a' }))
      .find('input')
      .attributes('id');
    const b = montar(campo({ name: 'b' }))
      .find('input')
      .attributes('id');

    expect(a).not.toBe(b);
  });

  it('o rótulo é obrigatório e recusa emoji', () => {
    expect(WField.props.label.required).toBe(true);
    expect(WField.props.label.validator('Tipo')).toBe(true);
    expect(WField.props.label.validator('Tipo 🎉')).toBe(false);
  });

  describe('a forma do controle por tipo do painel', () => {
    it('list vira <select> INDEXADO POR POSIÇÃO — a premissa do 3.15', () => {
      // `value="0"` para "Empresa" é exatamente o que o formulário guarda, e é
      // por isso que `show_if` precisa resolver antes de comparar. Se esta
      // asserção mudar, a resolução em `preChatFieldRules` deixa de fazer
      // sentido — e é bom que caia junto.
      const el = montar(
        campo({ type: 'list', values: ['Empresa', 'Pessoa física'] })
      );
      const opcoes = el.findAll('option');

      expect(el.find('select').exists()).toBe(true);
      expect(opcoes.map(o => o.attributes('value'))).toEqual(['0', '1']);
      expect(opcoes.map(o => o.text())).toEqual(['Empresa', 'Pessoa física']);
    });

    it('checkbox vira <input type=checkbox>', () => {
      const el = montar(campo({ type: 'checkbox' }));

      expect(el.find('input[type="checkbox"]').exists()).toBe(true);
    });

    it('link vira campo de url', () => {
      const el = montar(campo({ type: 'link' }));

      expect(el.find('input').attributes('type')).toBe('url');
    });

    it('text continua sendo texto, e o placeholder do painel chega ao campo', () => {
      const el = montar(campo({ placeholder: 'Diga o tipo' }));

      expect(el.find('input').attributes('type')).toBe('text');
      expect(el.find('input').attributes('placeholder')).toBe('Diga o tipo');
    });
  });

  describe('mensagens', () => {
    it('o erro delegado pelo formulário aparece no campo', async () => {
      const el = montar(campo({ validator: 'cpf' }), {
        errors: ['PRE_CHAT_FORM.VALIDATION.CPF'],
      });
      await el.vm.$nextTick();

      expect(el.text()).toContain('PRE_CHAT_FORM.VALIDATION.CPF');
    });

    it('o help_text do painel vira a ajuda do campo', () => {
      const el = montar(campo({ help_text: 'Como está no contrato' }));

      expect(el.text()).toContain('Como está no contrato');
    });

    it('a mensagem de obrigatório NOMEIA o campo (bloco 2.17)', () => {
      // Sem o rótulo no meio, três campos vazios diriam "Obrigatório" três
      // vezes e o leitor de tela não saberia de qual se trata.
      const el = montar(campo({ required: true }));

      expect(el.vm.validationMessages.required).toBe(
        'PRE_CHAT_FORM.FIELD_IS_REQUIRED'
      );
    });
  });

  describe('as regras que vão para o FormKit', () => {
    it('campo obrigatório carrega required; opcional carrega optional', () => {
      expect(montar(campo({ required: true })).vm.validation).toContainEqual([
        'required',
      ]);
      expect(montar(campo()).vm.validation).toContainEqual(['optional']);
    });

    it('emailAddress ganha a regra de e-mail', () => {
      const regras = montar(campo({ name: 'emailAddress' })).vm.validation;

      expect(regras).toContainEqual(['email']);
    });

    it('regex_pattern do painel vira `matches` SEM as flags g/y', () => {
      // O FormKit guarda a RegExp e chama `.test()` a cada tecla; com `g` o
      // `lastIndex` sobrevive entre chamadas e a validade oscila.
      const regras = montar(
        campo({
          field_type: 'contact_attribute',
          regex_pattern: '/^[a-z]+$/gi',
        })
      ).vm.validation;
      const matches = regras.find(regra => regra[0] === 'matches');

      expect(matches).toBeTruthy();
      expect(matches[1].flags).not.toContain('g');
      expect(matches[1].flags).not.toContain('y');
    });
  });

  it('o blur avisa o formulário com o nome do campo', async () => {
    const el = montar();
    await el.find('input').trigger('blur');

    expect(el.emitted('blur')[0]).toEqual(['tipo']);
  });
});

describe('WScrollToBottom', () => {
  const montar = (props = {}) =>
    mount(WScrollToBottom, {
      props: { label: 'Ver mensagens novas', ...props },
    });

  it('sem não lidas, o nome acessível é só o rótulo', () => {
    expect(montar().findComponent(WIconButton).props('label')).toBe(
      'Ver mensagens novas'
    );
  });

  it('com não lidas, o contador entra no NOME, não só no pixel', () => {
    const el = montar({ count: 3 });

    expect(el.findComponent(WIconButton).props('label')).toBe(
      'Ver mensagens novas (3)'
    );
    expect(el.find('.w-scroll-to-bottom__contador').text()).toBe('3');
  });

  it('zero não desenha contador', () => {
    expect(
      montar({ count: 0 }).find('.w-scroll-to-bottom__contador').exists()
    ).toBe(false);
  });

  it('count recusa negativo e fracionário', () => {
    const { validator } = WScrollToBottom.props.count;

    expect(validator(0)).toBe(true);
    expect(validator(-1)).toBe(false);
    expect(validator(2.5)).toBe(false);
  });

  it('emite click', async () => {
    const el = montar();
    await el.find('button').trigger('click');

    expect(el.emitted('click')).toHaveLength(1);
  });
});

describe('WTeaserCard', () => {
  const montar = () =>
    mount(WTeaserCard, {
      props: { dismissLabel: 'Dispensar convite' },
      slots: { default: 'Posso ajudar?' },
    });

  it('dispensar e abrir são alvos distintos, não o cartão inteiro', () => {
    const el = montar();

    expect(el.findAll('button')).toHaveLength(2);
  });

  it('o botão de dispensar tem nome acessível', () => {
    expect(montar().findComponent(WIconButton).props('label')).toBe(
      'Dispensar convite'
    );
  });

  it('emite open e dismiss separadamente', async () => {
    const el = montar();
    await el.find('.w-teaser-card__corpo').trigger('click');
    await el.findComponent(WIconButton).find('button').trigger('click');

    expect(el.emitted('open')).toHaveLength(1);
    expect(el.emitted('dismiss')).toHaveLength(1);
  });

  it('o rótulo de dispensar é obrigatório', () => {
    expect(WTeaserCard.props.dismissLabel.required).toBe(true);
  });
});

describe('WComposer', () => {
  const montar = (props = {}) =>
    mount(WComposer, { props: { label: 'Digite sua mensagem', ...props } });

  it('o campo tem rótulo associado e nome acessível', () => {
    const el = montar();
    const area = el.find('textarea');

    expect(el.find('label').attributes('for')).toBe(area.attributes('id'));
    expect(area.attributes('aria-label')).toBe('Digite sua mensagem');
  });

  it('Enter envia', async () => {
    const el = montar();
    await el.find('textarea').trigger('keydown', { key: 'Enter' });

    expect(el.emitted('submit')).toHaveLength(1);
  });

  describe('composição de IME — acentuação em teclado de celular', () => {
    // Digitar "café" em pt-BR passa por composição. Se o Enter que CONFIRMA o
    // acento for tratado como "enviar", a mensagem sai pela metade ("caf").
    // A fonte é o evento nativo, nunca timing.
    it('Enter durante a composição NÃO envia', async () => {
      const el = montar();
      const area = el.find('textarea');

      await area.trigger('compositionstart');
      await area.trigger('keydown', { key: 'Enter' });

      expect(el.emitted('submit')).toBeUndefined();
    });

    it('encerrada a composição, o Enter volta a enviar', async () => {
      const el = montar();
      const area = el.find('textarea');

      await area.trigger('compositionstart');
      await area.trigger('keydown', { key: 'Enter' });
      await area.trigger('compositionend');
      await area.trigger('keydown', { key: 'Enter' });

      expect(el.emitted('submit')).toHaveLength(1);
    });

    it('keydown com isComposing do próprio evento também barra', async () => {
      // Navegador que não emitiu compositionstart ainda pode marcar o keydown.
      const el = montar();

      await el.find('textarea').trigger('keydown', {
        key: 'Enter',
        isComposing: true,
      });

      expect(el.emitted('submit')).toBeUndefined();
    });

    it('keyCode 229 — o Enter que confirma o IME em vários navegadores', async () => {
      const el = montar();

      await el.find('textarea').trigger('keydown', {
        key: 'Enter',
        keyCode: 229,
      });

      expect(el.emitted('submit')).toBeUndefined();
    });
  });

  it('Shift+Enter NÃO envia — quebra linha', async () => {
    const el = montar();
    await el
      .find('textarea')
      .trigger('keydown', { key: 'Enter', shiftKey: true });

    expect(el.emitted('submit')).toBeUndefined();
  });

  it('enviar e anexar convivem: as ações são slot próprio', () => {
    const el = mount(WComposer, {
      props: { label: 'Digite' },
      slots: { actions: '<button>anexar</button><button>enviar</button>' },
    });

    expect(el.findAll('.w-composer__acoes button')).toHaveLength(2);
  });

  it('emite update:modelValue ao digitar', async () => {
    const el = montar();
    await el.find('textarea').setValue('oi');

    expect(el.emitted('update:modelValue')[0]).toEqual(['oi']);
  });
});
