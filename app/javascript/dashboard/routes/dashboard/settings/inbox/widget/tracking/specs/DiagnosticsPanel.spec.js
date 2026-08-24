import { config, mount } from '@vue/test-utils';
import DiagnosticsPanel from '../DiagnosticsPanel.vue';

/**
 * O ACEITE do bloco 5.14, do jeito que ele so vale:
 *
 *   "busca por `@` no painel RENDERIZADO -> vazio"
 *
 * Um teste que monta o painel com uma entrega SEM e-mail passa nesse aceite e
 * nao prova nada — o `@` nao aparece porque nunca entrou. Por isso todo caso
 * aqui FORCA a condicao ruim: a entrega chega com o e-mail do contato dentro,
 * pelos caminhos por onde ele chega de verdade.
 *
 * E ele chega por tres, nao por um:
 *
 *  1. `error_message` — o mais provavel, e o que o painel antigo desenhava cru.
 *     A Graph API da Meta ecoa o parametro ofensivo na mensagem de erro
 *     ("Invalid parameter: em (fulano@...) is not a valid hash"), e essa string
 *     vai inteira para `tracking_deliveries.error_message`;
 *  2. `field_names` com objeto no lugar de string, onde o e-mail e o VALOR;
 *  3. `field_names` com objeto onde o e-mail e a CHAVE — o caso que
 *     `Object.keys(...)[0]` sozinho nao pega, porque ali a chave e o vazamento.
 *
 * O primeiro caso e o que o painel anterior reprovava: ele renderizava
 * `{{ linha.error_message }}` sem tratamento nenhum.
 */
const [i18n] = config.global.plugins;
afterEach(() => {
  i18n.global.locale.value = 'en';
});

/** O e-mail de um contato real de lead — o dado que o aceite procura. */
const EMAIL_DO_CONTATO = 'ana.souza@empresa.com.br';
const TELEFONE_DO_CONTATO = '+55 65 99999-8888';

const entregaBase = {
  event_id: 'e1',
  name: 'chatspx_lead',
  destination: 'meta_capi',
  status: 'failed',
  http_status: 400,
  error_code: 'invalid_hash',
  emq: 4.2,
  last_attempted_at: '14:32:10',
  field_names: ['em', 'ph', 'external_id'],
};

const build = (props = {}) => {
  i18n.global.locale.value = 'pt_BR';
  return mount(DiagnosticsPanel, { props: { deliveries: [], ...props } });
};

describe('5.14 — o aceite: `@` no painel renderizado dá vazio', () => {
  it('o e-mail vindo dentro de `error_message` não é desenhado', () => {
    const wrapper = build({
      deliveries: [
        {
          ...entregaBase,
          // a forma REAL: o destino ecoa o parâmetro ofensivo
          error_message: `Invalid parameter: em (${EMAIL_DO_CONTATO}) is not a valid hash`,
        },
      ],
    });

    const texto = wrapper.text();
    expect(texto).not.toContain('@');
    expect(texto).not.toContain(EMAIL_DO_CONTATO);
    expect(texto).not.toContain('ana.souza');
    // e o suporte AINDA vê que houve erro e em qual campo — cortar o valor não
    // pode custar o diagnóstico, senão o painel deixa de servir para o que existe
    expect(texto).toContain('em');
    expect(texto).toContain('[oculto]');
  });

  it('o telefone vindo junto também não é desenhado', () => {
    const wrapper = build({
      deliveries: [
        {
          ...entregaBase,
          error_message: `ph ${TELEFONE_DO_CONTATO} rejected`,
        },
      ],
    });

    const texto = wrapper.text();
    expect(texto).not.toContain('99999');
    expect(texto).not.toContain('5565999998888');
    expect(texto).toContain('[oculto]');
  });

  it('valor que chegue dentro de `field_names` não é desenhado', () => {
    const wrapper = build({
      deliveries: [
        {
          ...entregaBase,
          field_names: [{ em: EMAIL_DO_CONTATO }, { ph: '1' }],
        },
      ],
    });

    expect(wrapper.text()).not.toContain('@');
    // a CHAVE sobrevive: é nome de campo, e é o que o suporte precisa ver
    expect(wrapper.find('[data-testid="fields-e1"]').text()).toBe('em, ph');
  });

  it('e-mail na POSIÇÃO DA CHAVE também não passa — é o caso que engana', () => {
    // `Object.keys(...)[0]` sozinho desenharia isto inteiro: aqui a chave É o
    // vazamento. Só validar o formato do nome resolve.
    const wrapper = build({
      deliveries: [
        { ...entregaBase, field_names: [{ [EMAIL_DO_CONTATO]: true }, 'em'] },
      ],
    });

    expect(wrapper.text()).not.toContain('@');
    expect(wrapper.find('[data-testid="fields-e1"]').text()).toBe('em');
  });

  it('o erro AGRUPADO passa pela mesma tesoura', () => {
    const wrapper = build({
      deliveries: [entregaBase],
      errorGroups: [
        {
          key: 'invalid_hash',
          count: 12,
          message: `em (${EMAIL_DO_CONTATO}) is not a valid hash`,
          httpStatus: 400,
        },
      ],
    });

    expect(wrapper.text()).not.toContain('@');
    expect(
      wrapper.find('[data-testid="diagnostics-error-groups"]').text()
    ).toContain('12×');
  });

  it('o retorno do botão de teste passa pela mesma tesoura', () => {
    const wrapper = build({
      testResult: {
        status: 'failed',
        http_status: 400,
        error_message: `em (${EMAIL_DO_CONTATO}) rejected`,
        field_names: [],
      },
    });

    expect(wrapper.text()).not.toContain('@');
    expect(
      wrapper.find('[data-testid="diagnostics-test-result"]').text()
    ).toContain('400');
  });
});

describe('5.14 — o painel responde "o evento saiu?" sem console', () => {
  it('mostra o status e o destino de cada tentativa', () => {
    const wrapper = build({
      deliveries: [
        { ...entregaBase, status: 'sent', http_status: 200, error_message: '' },
      ],
    });

    const linha = wrapper.find('[data-testid="delivery-e1-meta_capi"]');
    expect(linha.text()).toContain('meta_capi');
    expect(linha.text()).toContain('200');
    expect(linha.text()).toContain('4.2');
  });

  it('sem nenhuma entrega e com a rota no ar, diz que está vazio de verdade', () => {
    const wrapper = build({ deliveries: [] });

    expect(wrapper.find('[data-testid="diagnostics-empty"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="diagnostics-unavailable"]').exists()
    ).toBe(false);
  });

  it('sem a rota, NÃO diz "vazio" — diz qual caminho não respondeu', () => {
    const wrapper = build({
      deliveries: [],
      missingEndpoint: '/api/v1/accounts/3/inboxes/7/tracking_deliveries',
    });

    // a distinção que o aceite exige: "não saiu evento" e "ninguém consegue
    // ver" são respostas OPOSTAS para o cliente
    expect(wrapper.find('[data-testid="diagnostics-empty"]').exists()).toBe(
      false
    );
    expect(
      wrapper.find('[data-testid="diagnostics-unavailable"]').text()
    ).toContain('tracking_deliveries');
  });

  it('o EMQ aparece com a faixa saudável escrita na tela', () => {
    const wrapper = build({ deliveries: [entregaBase], emqAverage: 8.6 });

    expect(wrapper.find('[data-testid="diagnostics-emq"]').text()).toBe('8.6');
    expect(
      wrapper.find('[data-testid="diagnostics-summary"]').text()
    ).toContain('8');
  });
});
