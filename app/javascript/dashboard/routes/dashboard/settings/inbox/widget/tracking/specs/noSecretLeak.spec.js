import fs from 'fs';
import path from 'path';
import { mount } from '@vue/test-utils';
import DiagnosticsPanel from '../DiagnosticsPanel.vue';
import { PUBLIC_TRACKING_KEYS } from '../../composables/widgetTrackingContract';

/**
 * O aceite do 5.06 diz: **nenhum segredo em HTML, config, `index` ou log**.
 *
 * Sao QUATRO superficies distintas, e cada uma vaza de um jeito proprio:
 *
 *   1. **HTML** — `app/views/widgets/show.html.erb`, que vira o codigo-fonte de
 *      toda pagina do site do cliente;
 *   2. **config** — `configs/create.json.jbuilder`, o payload de boot;
 *   3. **index** — `_inbox.json.jbuilder`, o `GET` da inbox que qualquer agente
 *      com a caixa atribuida enxerga;
 *   4. **log** — o painel de diagnostico desta tela.
 *
 * As tres primeiras sao Ruby: aqui a verificacao e ESTATICA (o que os arquivos
 * interpolam) e esta declarada como tal — nao substitui um request spec, e o
 * relatorio diz isso. A quarta e comportamental e roda de verdade.
 */
const lerRaiz = relativo =>
  fs.readFileSync(path.resolve(process.cwd(), relativo), 'utf8');

const PADRAO_DE_SEGREDO = /(^|_)(token|secret)$/i;

/**
 * O VALOR que a view publica — nao o nome da chave. `json.widget_tracking` e o
 * nome do campo no JSON; o que importa e o que esta do lado direito.
 */
const valoresPublicados = conteudo =>
  [...conteudo.matchAll(/(?:json\.\w+|<%=)\s+([^\n%]+?)(?:%>|$)/gm)]
    .map(([, expressao]) => expressao.trim())
    .filter(expressao => /widget_tracking/.test(expressao));

/**
 * Os nomes que sao segredo de verdade nos destinos de anuncio. `tokens` (os
 * sete tokens de COR do bloco 1.02) e `website_token`/`hmac_token`/`pubsub`
 * sao identificadores publicos do widget e existem desde antes desta onda.
 */
const NOMES_DE_SEGREDO = [
  'access_token',
  'api_secret',
  'client_secret',
  'refresh_token',
  'capi_token',
  'meta_token',
];

describe('superfície 1 e 2 — o que vai para o site do cliente', () => {
  const erb = lerRaiz('app/views/widgets/show.html.erb');
  const jbuilder = lerRaiz(
    'app/views/api/v1/widget/configs/create.json.jbuilder'
  );

  it('os dois arquivos foram mesmo lidos', () => {
    expect(erb).toContain('chatwootWebChannel');
    expect(jbuilder).toContain('json.');
  });

  it.each([
    ['show.html.erb', erb],
    ['create.json.jbuilder', jbuilder],
  ])(
    '%s publica a PROJEÇÃO, nunca o hash cru de tracking',
    (_nome, conteudo) => {
      const usos = valoresPublicados(conteudo);

      expect(usos.length).toBeGreaterThan(0);
      // `public_widget_tracking` é a projeção por lista branca; `widget_tracking`
      // cru levaria junto o que alguém tenha gravado por outro caminho
      usos.forEach(uso =>
        expect({
          uso,
          projetado: uso.includes('public_widget_tracking'),
        }).toEqual({
          uso,
          projetado: true,
        })
      );
    }
  );

  it.each([
    ['show.html.erb', erb],
    ['create.json.jbuilder', jbuilder],
  ])(
    '%s não menciona nenhum segredo de destino de anúncio',
    (_nome, conteudo) => {
      const encontrados = NOMES_DE_SEGREDO.filter(nome =>
        new RegExp(nome, 'i').test(conteudo)
      );

      expect(encontrados).toEqual([]);
    }
  );
});

describe('superfície 3 — o `index` da inbox', () => {
  const inboxJbuilder = lerRaiz('app/views/api/v1/models/_inbox.json.jbuilder');

  it('devolve `additional_attributes`, e por isso a recusa na escrita é o que protege', () => {
    // O `index` devolve o hash inteiro (é assim desde antes desta onda). Logo, a
    // garantia não pode ser "a view filtra": ela é `SECRET_KEY_PATTERN`, que
    // RECUSA a escrita com 422. Este teste existe para que ninguém "resolva" o
    // problema filtrando aqui e ache que resolveu na origem.
    expect(inboxJbuilder).toContain('json.additional_attributes');

    const configuravel = lerRaiz('app/models/concerns/widget_configurable.rb');
    expect(configuravel).toContain('SECRET_KEY_PATTERN');
    expect(configuravel).toContain('ensure_no_secret_in_widget_config');
  });

  it('as chaves que a tela grava não casam com o padrão recusado', () => {
    expect(
      PUBLIC_TRACKING_KEYS.filter(chave => PADRAO_DE_SEGREDO.test(chave))
    ).toEqual([]);
  });
});

describe('superfície 4 — o log de diagnóstico', () => {
  const entrega = {
    event_id: 'a1b2',
    name: 'chatspx_lead',
    destination: 'meta_capi',
    status: 'sent',
    http_status: 200,
    last_attempted_at: '14:32:10',
    field_names: ['em', 'ph', 'fn'],
  };

  it('mostra os NOMES dos campos', () => {
    const wrapper = mount(DiagnosticsPanel, {
      props: { deliveries: [entrega] },
    });

    expect(wrapper.find('[data-testid="fields-a1b2"]').text()).toBe(
      'em, ph, fn'
    );
  });

  it('valor que chegue junto por engano NÃO é desenhado', () => {
    // defesa em profundidade: se um dia o servidor mandar `[{em: 'ana@x.com'}]`
    // no lugar de `['em']`, a tela ainda mostra só a chave
    const wrapper = mount(DiagnosticsPanel, {
      props: {
        deliveries: [
          {
            ...entrega,
            field_names: [
              { em: 'ana@exemplo.com.br' },
              { ph: '+5565999998888' },
            ],
          },
        ],
      },
    });

    const texto = wrapper.text();
    expect(wrapper.find('[data-testid="fields-a1b2"]').text()).toBe('em, ph');
    expect(texto).not.toContain('ana@exemplo.com.br');
    expect(texto).not.toContain('5565999998888');
  });

  it('o painel diz, na própria tela, que não mostra valores', () => {
    const wrapper = mount(DiagnosticsPanel, {
      props: { deliveries: [entrega] },
    });

    expect(wrapper.find('[data-testid="diagnostics-privacy"]').text()).toMatch(
      /nunca os valores|never the values/
    );
  });
});
