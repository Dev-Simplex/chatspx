import { mount } from '@vue/test-utils';
import WField from '../WField.vue';
import WScrollToBottom from '../WScrollToBottom.vue';
import WTeaserCard from '../WTeaserCard.vue';
import WComposer from '../WComposer.vue';
import WIconButton from '../WIconButton.vue';

describe('WField', () => {
  const montar = (props = {}) =>
    mount(WField, { props: { label: 'E-mail', ...props } });

  it('o rótulo aponta para o campo de verdade (for === id)', () => {
    // É esta ligação que separa "rótulo" de "texto solto ao lado". A violação
    // `label` medida pelo axe nos tipos ricos é exatamente a falta dela.
    const el = montar();
    const id = el.find('input').attributes('id');

    expect(id).toBeTruthy();
    expect(el.find('label').attributes('for')).toBe(id);
  });

  it('dois campos na mesma tela não colidem de id', () => {
    const a = montar().find('input').attributes('id');
    const b = montar().find('input').attributes('id');

    expect(a).not.toBe(b);
  });

  it('id explícito vence o gerado', () => {
    expect(montar({ id: 'meu-campo' }).find('input').attributes('id')).toBe(
      'meu-campo'
    );
  });

  it('erro: marca aria-invalid e aponta a mensagem por aria-describedby', () => {
    const el = montar({ error: 'E-mail inválido' });
    const input = el.find('input');
    const idErro = el.find('.w-field__erro').attributes('id');

    expect(input.attributes('aria-invalid')).toBe('true');
    expect(input.attributes('aria-describedby')).toContain(idErro);
    expect(el.find('.w-field__erro').text()).toBe('E-mail inválido');
  });

  it('sem erro não há aria-invalid', () => {
    expect(montar().find('input').attributes('aria-invalid')).toBeUndefined();
  });

  it('ajuda e erro juntos são ambos descritos', () => {
    const el = montar({ hint: 'Usamos para responder', error: 'Inválido' });
    const descritores = el.find('input').attributes('aria-describedby');

    expect(descritores.split(' ')).toHaveLength(2);
  });

  it('emite update:modelValue ao digitar', async () => {
    const el = montar();
    await el.find('input').setValue('ana@exemplo.com');

    expect(el.emitted('update:modelValue')[0]).toEqual(['ana@exemplo.com']);
  });

  it('o rótulo é obrigatório', () => {
    expect(WField.props.label.required).toBe(true);
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
