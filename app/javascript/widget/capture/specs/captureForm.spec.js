/**
 * Bloco 4.03 — o fluxo de captura conversacional.
 *
 * O aceite de LARGURA (4 campos em 375 px sem barra horizontal) é medido em
 * navegador de verdade, em `spec/e2e/widget/capture/`. Aqui ficam as regras de
 * comportamento, que layout nenhum prova: máscara no blur, validação BR, o teto
 * de 8 campos e a regra "e-mail OU WhatsApp".
 */
import { mount } from '@vue/test-utils';
import CaptureForm from '../CaptureForm.vue';
import CaptureField from '../CaptureField.vue';

const montarCampo = (field, props = {}) =>
  mount(CaptureField, {
    props: { field, modelValue: '', ...props },
    global: { mocks: { $t: k => k } },
  });

const montarFormulario = items =>
  mount(CaptureForm, {
    props: { items },
    global: { mocks: { $t: k => k } },
  });

const CAMPO_EMAIL = {
  name: 'email',
  label: 'E-mail',
  type: 'email',
  required: true,
  validator: 'email',
};
const CAMPO_WHATSAPP = {
  name: 'whatsapp',
  label: 'WhatsApp',
  type: 'phone',
  required: true,
  mask: 'phone',
  validator: 'phone',
};

describe('CaptureField — máscara no blur', () => {
  it('não reescreve o valor enquanto se digita', async () => {
    const wrapper = montarCampo({ name: 'cpf', label: 'CPF', mask: 'cpf' });

    await wrapper.find('input').setValue('12345678909');

    // `setValue` dispara `input`: o componente emite o valor CRU, sem separadores.
    const emitidos = wrapper.emitted('update:modelValue');
    expect(emitidos.at(-1)).toEqual(['12345678909']);
  });

  it('aplica a máscara de CPF no blur', async () => {
    const wrapper = montarCampo({ name: 'cpf', label: 'CPF', mask: 'cpf' });
    const input = wrapper.find('input');

    await input.setValue('12345678909');
    await input.trigger('blur');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      '123.456.789-09',
    ]);
  });

  it('aplica a máscara de CEP e a de UF no blur', async () => {
    const cep = montarCampo({ name: 'cep', label: 'CEP', mask: 'cep' });
    await cep.find('input').setValue('01310930');
    await cep.find('input').trigger('blur');
    expect(cep.emitted('update:modelValue').at(-1)).toEqual(['01310-930']);

    const uf = montarCampo({ name: 'uf', label: 'UF', mask: 'uf' });
    await uf.find('input').setValue('sp');
    await uf.find('input').trigger('blur');
    expect(uf.emitted('update:modelValue').at(-1)).toEqual(['SP']);
  });

  it('não toca no valor quando o campo não declara máscara', async () => {
    const wrapper = montarCampo({ name: 'nome', label: 'Nome' });
    const input = wrapper.find('input');

    await input.setValue('  Walisson  ');
    await input.trigger('blur');

    // Só o `input` emitiu; o blur não emitiu um valor diferente.
    expect(wrapper.emitted('update:modelValue')).toHaveLength(1);
  });
});

describe('CaptureField — validação', () => {
  it('marca aria-invalid e mostra a mensagem do código depois do blur', async () => {
    const wrapper = montarCampo({ ...CAMPO_EMAIL });
    const input = wrapper.find('input');

    await input.setValue('nao-e-email');
    await input.trigger('blur');

    expect(input.attributes('aria-invalid')).toBe('true');
    expect(wrapper.find('[role="alert"]').text()).toBe(
      'CAPTURE.VALIDATION.EMAIL'
    );
  });

  it('prefere a mensagem que o cliente escreveu no construtor', async () => {
    const wrapper = montarCampo({
      ...CAMPO_EMAIL,
      error_message: 'Precisamos do e-mail do trabalho',
    });
    const input = wrapper.find('input');

    await input.setValue('nao-e-email');
    await input.trigger('blur');

    expect(wrapper.find('[role="alert"]').text()).toBe(
      'Precisamos do e-mail do trabalho'
    );
  });

  it('não mostra erro antes de a pessoa sair do campo', async () => {
    const wrapper = montarCampo({ ...CAMPO_EMAIL });

    await wrapper.find('input').setValue('ainda-digitando');

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('um validador `junk_*` avisa mas NÃO invalida (severidade warning, decisão do 3.13)', async () => {
    const wrapper = montarCampo({
      name: 'nome',
      label: 'Nome',
      validator: 'junk_name',
    });
    const input = wrapper.find('input');

    // `qwrt` não tem vogal — é a regra 1 do anti-lixo do 3.13 (`looksLikeJunkName`).
    await input.setValue('qwrt');
    await input.trigger('blur');

    expect(wrapper.find('[role="alert"]').text()).toBe(
      'CAPTURE.VALIDATION.JUNK_NAME'
    );
    expect(input.attributes('aria-invalid')).toBe('false');
    expect(wrapper.emitted('validity').at(-1)).toEqual([
      { name: 'nome', valid: true },
    ]);
  });
});

describe('CaptureForm — teto de 8 campos', () => {
  it('desenha no máximo 8 campos, mesmo com 12 no passo', () => {
    const items = Array.from({ length: 12 }, (_, i) => ({
      name: `campo${i}`,
      label: `Campo ${i}`,
      validator: 'junk_name',
    }));

    const wrapper = montarFormulario(items);

    expect(wrapper.findAllComponents(CaptureField)).toHaveLength(8);
  });

  it('descarta campo sem nome', () => {
    const wrapper = montarFormulario([
      { label: 'sem nome', mask: 'cpf' },
      { name: 'ok', label: 'Ok', mask: 'cpf' },
    ]);

    expect(wrapper.findAllComponents(CaptureField)).toHaveLength(1);
  });
});

describe('CaptureForm — e-mail OU WhatsApp', () => {
  const montarContato = () =>
    montarFormulario([
      { name: 'nome', label: 'Nome', required: true, validator: 'junk_name' },
      CAMPO_EMAIL,
      CAMPO_WHATSAPP,
    ]);

  it('bloqueia o envio enquanto nenhum canal de contato foi preenchido', async () => {
    const wrapper = montarContato();

    await wrapper
      .findAllComponents(CaptureField)[0]
      .find('input')
      .setValue('Walisson');

    expect(
      wrapper.find('[data-testid="capture-submit"]').attributes('disabled')
    ).toBeDefined();
  });

  it('libera o envio com SÓ o e-mail — não exige os dois', async () => {
    const wrapper = montarContato();
    const campos = wrapper.findAllComponents(CaptureField);

    await campos[0].find('input').setValue('Walisson');
    await campos[1].find('input').setValue('walisson@empresa.com.br');
    await campos[1].find('input').trigger('blur');

    expect(
      wrapper.find('[data-testid="capture-submit"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('libera o envio com SÓ o WhatsApp', async () => {
    const wrapper = montarContato();
    const campos = wrapper.findAllComponents(CaptureField);

    await campos[0].find('input').setValue('Walisson');
    await campos[2].find('input').setValue('+55 11 99999-8888');
    await campos[2].find('input').trigger('blur');

    expect(
      wrapper.find('[data-testid="capture-submit"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('mostra a dica do grupo só quando o grupo existe', () => {
    expect(montarContato().text()).toContain('CAPTURE.CONTACT_GROUP_HINT');

    const semGrupo = montarFormulario([
      { name: 'nome', label: 'Nome', required: true, validator: 'junk_name' },
      CAMPO_EMAIL,
    ]);
    expect(semGrupo.text()).not.toContain('CAPTURE.CONTACT_GROUP_HINT');
  });

  it('continua exigindo o campo de contato ser VÁLIDO, não só preenchido', async () => {
    const wrapper = montarContato();
    const campos = wrapper.findAllComponents(CaptureField);

    await campos[0].find('input').setValue('Walisson');
    await campos[1].find('input').setValue('nao-e-email');
    await campos[1].find('input').trigger('blur');

    expect(
      wrapper.find('[data-testid="capture-submit"]').attributes('disabled')
    ).toBeDefined();
  });

  it('emite os valores no formato que o backend grava em submitted_values', async () => {
    const wrapper = montarContato();
    const campos = wrapper.findAllComponents(CaptureField);

    await campos[0].find('input').setValue('Walisson');
    await campos[1].find('input').setValue('walisson@empresa.com.br');
    await campos[1].find('input').trigger('blur');
    await wrapper.find('[data-testid="capture-form"]').trigger('submit');

    expect(wrapper.emitted('submit').at(-1)).toEqual([
      [
        { name: 'nome', value: 'Walisson' },
        { name: 'email', value: 'walisson@empresa.com.br' },
        { name: 'whatsapp', value: '' },
      ],
    ]);
  });
});
