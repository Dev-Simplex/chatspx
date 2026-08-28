import { readFileSync } from 'node:fs';
import { mount } from '@vue/test-utils';
import Form from '../Form.vue';
import PreChatBody from '../PreChatBody.vue';

/**
 * O ACEITE NUMÉRICO DO R15, executável.
 *
 * `PreChat/Form.vue` é um dos três campos minados do widget: o upstream o
 * reescreve a cada minor (+39/−33 medidos), e cada linha nossa dentro dele é
 * conflito garantido na próxima subida de versão. A mitigação do R15 é casca
 * fina, e o aceite mede: **menos de 60 linhas**.
 *
 * Um número num relatório não impede o arquivo de voltar a engordar; este teste
 * impede. Ele é o motivo de a regra, o estado e a marcação terem saído dali —
 * se alguém devolver qualquer uma delas, cai aqui e não em produção.
 */
const TETO = 60;
const CASCA = 'app/javascript/widget/components/PreChat/Form.vue';

describe('3.15 — a casca de PreChat/Form.vue', () => {
  it(`tem menos de ${TETO} linhas`, () => {
    const linhas = readFileSync(CASCA, 'utf8').split('\n').length;

    // Guarda contra o falso verde óbvio: arquivo que sumiu ou caminho errado
    // leriam zero, e zero é "menos de 60".
    expect(linhas).toBeGreaterThan(0);
    expect(linhas).toBeLessThan(TETO);
  });

  it('não guarda estado nem regra: nem data, nem computed, nem methods', () => {
    // As três chaves são exatamente o que estava lá dentro antes (formValues,
    // enabledPreChatFields, onSubmit e companhia). Casca não tem nenhuma.
    expect(Form.data).toBeUndefined();
    expect(Form.computed).toBeUndefined();
    expect(Form.methods).toBeUndefined();
  });

  it('delega o corpo, e repassa as opções que recebeu', () => {
    const options = { preChatFields: [], preChatMessage: 'Oi' };
    const wrapper = mount(Form, {
      props: { options },
      global: { stubs: { PreChatBody: true } },
    });

    expect(wrapper.findComponent(PreChatBody).props('options')).toEqual(
      options
    );
  });

  it('reemite submitPreChat com a carga intacta', async () => {
    const carga = { fullName: 'Ana', message: 'oi' };
    const wrapper = mount(Form, {
      props: { options: { preChatFields: [], preChatMessage: '' } },
      global: { stubs: { PreChatBody: true } },
    });

    await wrapper.findComponent(PreChatBody).vm.$emit('submitPreChat', carga);

    expect(wrapper.emitted('submitPreChat')).toEqual([[carga]]);
  });
});
