import fs from 'fs';
import path from 'path';
import { API } from 'widget/helpers/axios';
import { SDK_APPEARANCE_OVERRIDES } from 'shared/constants/sharedFrameEvents';
import handlers from 'widget/bridge/handlers';

/**
 * Bloco 3.18 — o lado do iframe do relatorio de precedencia.
 *
 * O host mede (e o unico que enxerga o `chatwootSettings` do site), a ponte
 * carrega, e ESTE modulo grava. Sem ele, `widget_appearance_overrides` continua
 * sendo uma chave que a tela le e que ninguem escreve.
 *
 * O QUE ESTE ARQUIVO DEIXAVA PASSAR, E QUE AGORA NAO DEIXA
 *
 * Ele afirmava `API.post('/api/v1/widget/appearance_overrides', { fields })` e
 * ficava verde — enquanto o servidor respondia **404** a essa exata requisicao,
 * porque todo endpoint do widget exige `website_token` (`set_web_widget`, em
 * `app/controllers/concerns/website_token_helper.rb`). Medir "a funcao chamou o
 * axios" nao mede "o servidor recebeu". Por isso aqui as assercoes passaram a ser
 * sobre a URL montada, e a prova de que ela chega ao Rails mora no request spec
 * `spec/controllers/api/v1/widget/appearance_overrides_request_spec.rb`, que
 * EXECUTA `appearanceOverridesRequest.js` e manda ao servidor o que sair de la.
 */
vi.mock('widget/helpers/axios', () => ({
  API: { post: vi.fn(() => Promise.resolve()) },
}));

const CAMINHO = '/api/v1/widget/appearance_overrides';
const TOKEN_DO_SITE = 'aBcD1234websiteToken';

// O `search` que o iframe realmente tem: `sdk/IFrameHelper.js` monta o `src` como
// `${baseUrl}/widget?website_token=${websiteToken}` e cola `&cw_conversation=` quando ha cookie.
const comSearchDoIframe = () =>
  window.history.replaceState(
    {},
    '',
    `/widget?website_token=${TOKEN_DO_SITE}&cw_conversation=cookie-de-sessao`
  );

describe('3.18 — registro das sobrescritas do site', () => {
  let registrarSobrescritasDoSite;

  beforeEach(async () => {
    vi.resetModules();
    API.post.mockClear();
    comSearchDoIframe();
    ({ registrarSobrescritasDoSite } = await import('../appearanceOverrides'));
  });

  it('manda a lista de campos para o endpoint do widget, COM o `website_token`', async () => {
    await registrarSobrescritasDoSite({ fields: ['theme', 'position'] });

    expect(API.post).toHaveBeenCalledWith(
      `${CAMINHO}?website_token=${TOKEN_DO_SITE}`,
      { fields: ['theme', 'position'] }
    );
  });

  it('lista VAZIA viaja — e o que apaga um aviso que ficou velho', async () => {
    await registrarSobrescritasDoSite({ fields: [] });

    expect(API.post).toHaveBeenCalledWith(
      `${CAMINHO}?website_token=${TOKEN_DO_SITE}`,
      { fields: [] }
    );
  });

  it('sem `fields` nao chama nada — ausencia nao e medicao', async () => {
    await registrarSobrescritasDoSite({});
    await registrarSobrescritasDoSite();

    expect(API.post).not.toHaveBeenCalled();
  });

  it('sem `website_token` na URL do iframe nao ha ida a rede — seria 404 certo', async () => {
    window.history.replaceState({}, '', '/widget?cw_conversation=so-o-cookie');

    await registrarSobrescritasDoSite({ fields: ['position'] });

    expect(API.post).not.toHaveBeenCalled();
  });

  it('falha do servidor nao vaza para o site do cliente', async () => {
    API.post.mockRejectedValueOnce(new Error('500'));

    // Nenhuma falha de relatorio pode virar `unhandledrejection` no rastreador
    // de erros do CLIENTE — mesma regra do 4.18 e do 4.21.
    await expect(
      registrarSobrescritasDoSite({ fields: ['position'] })
    ).resolves.toBeUndefined();
  });
});

describe('3.18 — as duas pontas da ponte falam o mesmo nome', () => {
  beforeEach(() => {
    comSearchDoIframe();
  });

  it('a ponte tem handler para a mensagem que o host emite', () => {
    // Nome divergente num `postMessage` nao produz erro: o host manda, ninguem
    // escuta, e o recurso simplesmente nao acontece — o modo de falha do 5.10 e
    // do 2.16 nesta base. A constante compartilhada torna isso impossivel; esta
    // assercao trava a constante ao mapa.
    expect(typeof handlers[SDK_APPEARANCE_OVERRIDES]).toBe('function');
  });

  it('o handler encaminha a mensagem para o registro', async () => {
    vi.resetModules();
    API.post.mockClear();

    handlers[SDK_APPEARANCE_OVERRIDES]({ fields: ['position'] });
    await Promise.resolve();

    expect(API.post).toHaveBeenCalledWith(
      `${CAMINHO}?website_token=${TOKEN_DO_SITE}`,
      { fields: ['position'] }
    );
  });
});

describe('3.18 — o caminho existe do outro lado', () => {
  it('a rota que o widget chama esta declarada no `config/routes.rb`', () => {
    // O modo de falha que isto cobre e o de `5.04`/`5.05` nesta base: o cliente
    // chama um caminho que o servidor nao roteia, o `catch` de melhor esforco
    // engole o 404 e o recurso fica morto sem uma linha vermelha em lugar nenhum.
    //
    // Ele NAO cobre o modo de falha que de fato aconteceu aqui: a rota existia, o
    // controller existia, e a requisicao mesmo assim era 404 por falta do
    // `website_token`. Quem cobre isso e o request spec, que atravessa a junta.
    const rotas = fs.readFileSync(
      path.resolve(process.cwd(), 'config/routes.rb'),
      'utf8'
    );
    const semComentarios = rotas
      .split('\n')
      .filter(linha => !linha.trim().startsWith('#'))
      .join('\n');

    expect(semComentarios).toMatch(
      /resource :appearance_overrides.*controller: 'appearance_overrides'/
    );
  });
});
