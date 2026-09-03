/**
 * Bloco 4.03 — qual dos dois formulários o passo recebe, e por quê.
 *
 * A escolha é pelo CONTEÚDO do passo (declarou máscara/validador/telefone?), não
 * por configuração de conta. O que este spec protege é a NÃO-REGRESSÃO: um `form`
 * gravado antes deste bloco não tem nenhuma dessas chaves e precisa continuar
 * caindo no `ChatForm` de sempre.
 */
import { shallowMount } from '@vue/test-utils';
import FormContent from '../FormContent.vue';

const montar = messageContentAttributes =>
  shallowMount(FormContent, {
    props: { messageId: 1, messageContentAttributes },
    global: { mocks: { $t: k => k } },
  });

const nome = (extra = {}) => ({
  name: 'nome',
  label: 'Nome',
  type: 'text',
  ...extra,
});

describe('4.03 — FormContent escolhe o formulário pelo conteúdo do passo', () => {
  it('usa o ChatForm de sempre num formulário sem máscara, validador ou telefone', () => {
    const wrapper = montar({
      items: [nome(), { name: 'email', type: 'email' }],
    });

    expect(wrapper.findComponent({ name: 'ChatForm' }).exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'CaptureForm' }).exists()).toBe(false);
  });

  it.each([
    ['máscara', nome({ mask: 'cpf' })],
    ['validador', nome({ validator: 'junk_name' })],
    ['campo de telefone', { name: 'zap', type: 'phone' }],
  ])('usa o CaptureForm quando o passo declara %s', (_rotulo, item) => {
    const wrapper = montar({ items: [item] });

    expect(wrapper.findComponent({ name: 'CaptureForm' }).exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'ChatForm' }).exists()).toBe(false);
  });

  it('não desenha formulário nenhum depois de respondido (comportamento de hoje)', () => {
    const wrapper = montar({
      items: [nome({ mask: 'cpf' })],
      submitted_values: [{ name: 'nome', value: 'Walisson' }],
    });

    expect(wrapper.findComponent({ name: 'CaptureForm' }).exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'ChatForm' }).exists()).toBe(false);
  });

  it('repassa a submissão do CaptureForm no MESMO formato do ChatForm', async () => {
    const wrapper = montar({ items: [nome({ mask: 'cpf' })] });
    const valores = [{ name: 'nome', value: 'Walisson' }];

    wrapper.findComponent({ name: 'CaptureForm' }).vm.$emit('submit', valores);
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('response').at(-1)).toEqual([
      { submittedValues: valores, messageId: 1 },
    ]);
  });
});
