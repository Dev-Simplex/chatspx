import { mount } from '@vue/test-utils';
import WebhookForm from '../WebhookForm.vue';

/**
 * Bloco 4.14 — o ACEITE diz que o `index` nao expoe segredo. Mas parar o servidor de
 * devolve-lo nao basta, e este arquivo existe por causa do caminho que sobra:
 *
 *   1. criar um webhook devolve o segredo UMA vez (e o unico momento de copia-lo);
 *   2. `webhooks/create` no store comita esse objeto INTEIRO em `records`;
 *   3. a lista le `records`, e "Editar" passa o registro escolhido para este formulario;
 *   4. o formulario lia `value.secret` e o DESENHAVA.
 *
 * Ou seja: o segredo continuava chegando a tela pelo residuo da criacao no store, mesmo com
 * o `index` ja limpo. E o mesmo formato de defeito que esta base ja teve em
 * `Integrations::Hook` — a resposta filtra o campo e o front o reintroduz pelo outro lado.
 *
 * Por isso a busca e feita no HTML RENDERIZADO, com um `value` QUE TEM segredo: e exatamente
 * a forma do registro que o store guarda logo depois de criar. Rodar com `secret` vazio
 * mediria zero e passaria sozinho.
 */
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ inboxEventsEnabled: false }),
}));

const SEGREDO = 'wh_sec_9f3c1a77b2e64d0a8c5b1e2f3a4d5c6e';

/** A forma REAL do registro no store logo apos `webhooks/create`. */
const webhookRecemCriado = {
  id: 7,
  name: 'Meu webhook',
  url: 'https://destino.exemplo.com/h',
  subscriptions: ['conversation_created'],
  secret: SEGREDO,
  has_secret: true,
};

const montar = (value = webhookRecemCriado) =>
  mount(WebhookForm, {
    props: { value, submitLabel: 'Salvar' },
  });

describe('4.14 — o segredo nao e desenhado no formulario', () => {
  it('o dado de entrada TEM segredo — senao esta busca mede zero', () => {
    expect(webhookRecemCriado.secret).toBe(SEGREDO);
    expect(SEGREDO.length).toBeGreaterThan(20);
  });

  it('o segredo nao esta no HTML de PARTIDA', () => {
    const wrapper = montar();

    expect(wrapper.html()).not.toContain(SEGREDO);
    expect(wrapper.text()).not.toContain(SEGREDO);
  });

  /**
   * ESTE e o teste que acusa, e a assercao acima NAO era ele.
   *
   * No formulario antigo o segredo nascia mascarado e so aparecia depois que o usuario
   * clicava no olho. Uma busca no HTML de partida, portanto, passava com o defeito INTEIRO
   * no lugar — media zero. O estado de repouso nao e a pergunta; a pergunta e se EXISTE
   * caminho, na tela, que leve o segredo ao DOM.
   *
   * Entao a condicao e forcada de duas formas, e as duas descrevem um usuario real:
   * clicar em tudo que a tela oferece, e — se a tela ainda tiver o estado de revelar —
   * liga-lo na marra.
   */
  it('NENHUMA interacao da tela leva o segredo ao DOM', async () => {
    const wrapper = montar();

    // Em cadeia, e nao em paralelo: cada clique e assertado logo depois dele proprio.
    // Um `Promise.all` clicaria tudo junto e um botao que ALTERNA (era o caso do olho)
    // poderia voltar ao estado mascarado antes da unica assercao do fim.
    await wrapper.findAll('button').reduce(
      (anterior, botao) =>
        anterior.then(async () => {
          await botao.trigger('click');
          expect(wrapper.html()).not.toContain(SEGREDO);
        }),
      Promise.resolve()
    );

    // O formulario antigo guardava `secretVisible`. Se algum dia ele voltar, este bloco
    // liga o estado e a assercao seguinte pega o vazamento.
    if (wrapper.vm.secretVisible !== undefined) {
      await wrapper.setData({ secretVisible: true });
    }

    expect(wrapper.html()).not.toContain(SEGREDO);
    const valores = wrapper.findAll('input').map(i => i.element.value);
    expect(valores).not.toContain(SEGREDO);
    expect(valores.join(' ')).not.toContain('wh_sec_');
  });

  it('nao existe controle de revelar segredo — nem escondido', () => {
    const wrapper = montar();

    expect(wrapper.html()).not.toContain('i-lucide-eye');
    expect(wrapper.vm.secretVisible).toBeUndefined();
  });
});

describe('4.14 — a tela diz que EXISTE segredo, sem dizer qual', () => {
  it('com `has_secret` a tela mostra o campo mascarado', () => {
    const wrapper = montar();

    expect(wrapper.vm.hasSecret).toBe(true);
    expect(wrapper.html()).toContain('••••');
  });

  // Esta e a metade que o defeito ESCONDIA: depois de um F5 o `index` devolve
  // `has_secret: true` e nenhum `secret`. Lendo `value.secret`, o bloco sumia inteiro e a
  // tela passava a negar a existencia de um segredo que existe.
  it('depois do F5, sem `secret` no payload, a tela AINDA afirma que ha segredo', () => {
    const wrapper = montar({
      id: 7,
      url: 'https://destino.exemplo.com/h',
      subscriptions: ['conversation_created'],
      has_secret: true,
    });

    expect(wrapper.vm.hasSecret).toBe(true);
    expect(wrapper.html()).toContain('••••');
  });

  it('webhook sem segredo nenhum nao mostra o campo', () => {
    const wrapper = montar({
      id: 8,
      url: 'https://outro.exemplo.com/h',
      subscriptions: ['conversation_created'],
      has_secret: false,
    });

    expect(wrapper.vm.hasSecret).toBe(false);
    expect(wrapper.html()).not.toContain('••••');
  });
});
