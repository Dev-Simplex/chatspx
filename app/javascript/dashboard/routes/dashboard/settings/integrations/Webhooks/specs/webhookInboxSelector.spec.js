import { createStore } from 'vuex';
import { mount } from '@vue/test-utils';
import WebhookForm from '../WebhookForm.vue';

/**
 * Bloco 4.13 — o seletor de inbox.
 *
 * O `inbox_id` existia no banco, no `permit` do controller e no serializador; o que nunca
 * existiu foi a forma de escolher. Com a entrega passando a respeitar o campo, um webhook
 * preso a uma inbox so podia ser criado chamando a API na mao — pela tela era
 * inalcancavel.
 *
 * O que este arquivo mede e o CONTRATO da tela com o servidor: o que sai no `submit`. Uma
 * verificacao que so olhasse o HTML do `<select>` passaria com um campo bonito que nao
 * manda nada.
 */
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ inboxEventsEnabled: false }),
}));

const INBOXES = [
  { id: 11, name: 'Site' },
  { id: 22, name: 'WhatsApp' },
];

const criarStore = (inboxes = INBOXES) =>
  createStore({
    modules: {
      inboxes: {
        namespaced: true,
        getters: { getInboxes: () => inboxes },
      },
    },
  });

const montar = (value = {}, inboxes = INBOXES) =>
  mount(WebhookForm, {
    props: { value, submitLabel: 'Salvar' },
    global: { plugins: [criarStore(inboxes)] },
  });

const submeter = async wrapper => {
  await wrapper.find('form').trigger('submit');
  return wrapper.emitted('submit').at(-1)[0];
};

describe('4.13 — o seletor de inbox do webhook', () => {
  it('lista todas as inboxes da conta, mais a opcao de nao escolher nenhuma', () => {
    const opcoes = montar().findAll('#webhook-inbox option');

    expect(opcoes).toHaveLength(INBOXES.length + 1);
    expect(opcoes[0].element.value).toBe('');
    expect(opcoes.slice(1).map(o => o.text())).toEqual(['Site', 'WhatsApp']);
  });

  it('webhook novo nasce sem inbox — recebe tudo, como quem nunca preencheu o campo', async () => {
    const wrapper = montar();

    expect(wrapper.find('#webhook-inbox').element.value).toBe('');
    expect(await submeter(wrapper)).toMatchObject({ inbox_id: null });
  });

  it('escolher uma inbox manda o id dela no submit', async () => {
    const wrapper = montar();

    await wrapper.find('#webhook-inbox').setValue(22);

    expect(await submeter(wrapper)).toMatchObject({ inbox_id: 22 });
  });

  /**
   * Trava o TIPO, nao so o valor: `inbox_id` e inteiro no banco, e uma string faria o
   * servidor depender do cast do Rails. Hoje o `:value` do `<option>` ja carrega o id
   * como numero — medido: este exemplo continua verde mesmo sem a conversao no `submit`.
   * Ele nao esta aqui para pegar a conversao, e sim para que trocar o `:value` por um
   * atributo cru (que viraria string) caia AQUI e nao no cliente.
   */
  it('o id vai como numero, nunca como string', async () => {
    const wrapper = montar();

    await wrapper.find('#webhook-inbox').setValue(11);

    expect(await submeter(wrapper).then(p => typeof p.inbox_id)).toBe('number');
  });

  /**
   * O `index` serializa a inbox como objeto aninhado (`inbox: { id, name }`), e nao como
   * `inbox_id`. Ler o campo errado deixaria o seletor sempre em "todas" ao abrir "Editar"
   * — e salvar sem tocar nele DESPRENDERIA o webhook da inbox, em silencio.
   */
  it('ao editar, parte da inbox que o servidor devolveu', async () => {
    const wrapper = montar({
      id: 7,
      url: 'https://destino.exemplo.com/h',
      subscriptions: ['conversation_created'],
      inbox: { id: 22, name: 'WhatsApp' },
    });

    expect(wrapper.find('#webhook-inbox').element.value).toBe('22');
    expect(await submeter(wrapper)).toMatchObject({ inbox_id: 22 });
  });

  it('e voltar para "todas as inboxes" desprende o webhook', async () => {
    const wrapper = montar({
      id: 7,
      url: 'https://destino.exemplo.com/h',
      subscriptions: ['conversation_created'],
      inbox: { id: 22, name: 'WhatsApp' },
    });

    await wrapper.find('#webhook-inbox').setValue('');

    expect(await submeter(wrapper)).toMatchObject({ inbox_id: null });
  });

  it('conta sem inbox nenhuma ainda oferece a opcao de receber tudo', () => {
    const opcoes = montar({}, []).findAll('#webhook-inbox option');

    expect(opcoes).toHaveLength(1);
    expect(opcoes[0].element.value).toBe('');
  });
});
