import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { resetarProvedorParaTestes } from '../identityToken';
import {
  STATUS_ACEITO,
  STATUS_ENFILEIRADO,
  STATUS_DEDUPLICADO,
} from '../callResult';

/**
 * A COSTURA entre o bloco 5.17 (resultado tipado) e o 5.19 (credencial por callback).
 *
 * POR QUE ESTE ARQUIVO EXISTE. Os dois blocos foram escritos em paralelo, cada um reescrevendo por
 * conta propria a MESMA callback de despacho do `setUser` em `entrypoints/sdk.js`. Nenhum dos dois
 * sabia do outro, entao nenhuma das duas suites consegue medir o que so aparece quando os dois
 * estao na arvore junto: um despacho que agora e ADIADO por uma promessa (5.19) e que precisa,
 * mesmo assim, devolver o `{ deduplicated }` que o resultado tipado (5.17) le.
 *
 * `identityTokenProvider.spec.js` mede o provedor assincrono, mas nunca olha o `status` do
 * resultado. `resultadoTipadoEEstado.spec.js` mede o `status`, mas sempre sem provedor — o
 * caminho sincrono. O cruzamento dos dois — provedor assincrono E resultado tipado — nao era
 * medido em lugar nenhum, e e exatamente onde a reconciliacao pode falhar em silencio: bastaria o
 * retorno da callback nao subir pela promessa de `entao` para todo `setUser` de um site com
 * provedor assincrono passar a responder `accepted` mesmo quando nao mandou nada.
 *
 * O CAMINHO QUE ESTE ARQUIVO PERCORRE, e por que ele fecha: a callback devolve
 * `{ deduplicated }` -> `entao` devolve `valor.then(fn)` quando o provedor e assincrono, ou o
 * retorno cru de `fn` quando nao e -> `enfileirar` faz `Promise.resolve(despachar())`, que
 * desembrulha a promessa nos dois casos -> `chamadaDeDados` le `retorno?.deduplicated`.
 *
 * Por que jsdom basta: nada aqui e cascade nem layout, e contrato de objeto e ordem de mensagem.
 */
describe('reconciliacao 5.17 + 5.19 — o resultado tipado atravessa o adiamento da credencial', () => {
  let enviadas;
  let IFrameHelper;

  beforeEach(async () => {
    document.body.innerHTML = '';
    delete window.$chatwoot;
    window.chatwootSettings = {};
    enviadas = [];
    resetarProvedorParaTestes();
    vi.spyOn(console, 'error').mockImplementation(() => {});

    if (!window.matchMedia) {
      window.matchMedia = () => ({
        matches: false,
        addEventListener: () => {},
        removeEventListener: () => {},
      });
    }

    // A ORDEM IMPORTA — mesma razao das outras duas suites: `resetModules` faz o entrypoint
    // importar uma instancia NOVA de `IFrameHelper`, e espionar a antiga nao intercepta nada.
    vi.resetModules();
    ({ IFrameHelper } = await import('../IFrameHelper'));
    vi.spyOn(IFrameHelper, 'sendMessage').mockImplementation((key, value) => {
      enviadas.push({ key, value });
    });

    await import('../../entrypoints/sdk.js');
    window.chatwootSDK.run({
      baseUrl: 'https://exemplo.test',
      websiteToken: 'tok-recon',
    });
  }, 20000);

  afterEach(() => {
    vi.restoreAllMocks();
    document.cookie =
      'cw_user_tok-recon=; expires=Thu, 01 Jan 1970 00:00:00 GMT';
  });

  const drenar = async () => {
    const iframe = document.createElement('iframe');
    iframe.id = 'chatwoot_live_chat_widget';
    document.body.appendChild(iframe);
    IFrameHelper.events.loaded({
      config: { authToken: 'jwt', channelConfig: {} },
    });
    await Promise.resolve();
    await Promise.resolve();
  };

  const doTipo = tipo => enviadas.filter(m => m.key === tipo);

  it('provedor ASSINCRONO: a primeira identificacao resolve como ACEITA e leva a credencial', async () => {
    window.$chatwoot.setIdentityTokenProvider(() =>
      Promise.resolve('jwt.assincrono')
    );
    await drenar();

    const r = await window.$chatwoot.setUser('CRM-1', { name: 'Ana' });

    expect(r.status).toBe(STATUS_ACEITO);
    expect(doTipo('set-user')).toHaveLength(1);
    expect(doTipo('set-user')[0].value.user.identity_token).toBe(
      'jwt.assincrono'
    );
  });

  /**
   * O EXEMPLO QUE JUSTIFICA O ARQUIVO.
   *
   * Com provedor assincrono, `despachar()` deixa de devolver o objeto e passa a devolver uma
   * PROMESSA dele. Se o `{ deduplicated: true }` nao sobreviver a essa travessia, a saida
   * antecipada volta a ser muda — que e o defeito inteiro que o 5.17 existe para fechar — e volta
   * muda SO para os sites que usam credencial, que sao justamente os que mais identificam.
   */
  it('provedor ASSINCRONO: a segunda identificacao IGUAL diz `deduplicated`, e nao manda nada', async () => {
    window.$chatwoot.setIdentityTokenProvider(() =>
      Promise.resolve('jwt.assincrono')
    );
    await drenar();

    const usuario = { name: 'Ana', email: 'ana@exemplo.com.br' };
    const primeira = await window.$chatwoot.setUser('CRM-1', usuario);
    expect(primeira.status).toBe(STATUS_ACEITO);

    const segunda = await window.$chatwoot.setUser('CRM-1', usuario);

    expect(segunda.status).toBe(STATUS_DEDUPLICADO);
    expect(segunda.reason).toContain('identical');
    // A prova de que a deduplicacao aconteceu de fato: nenhuma mensagem NOVA saiu.
    expect(doTipo('set-user')).toHaveLength(1);
  });

  it('provedor SINCRONO: o mesmo `deduplicated`, pelo caminho que nao passa por promessa', async () => {
    window.$chatwoot.setIdentityTokenProvider(() => 'jwt.sincrono');
    await drenar();

    const usuario = { name: 'Ana' };
    await window.$chatwoot.setUser('CRM-1', usuario);
    const segunda = await window.$chatwoot.setUser('CRM-1', usuario);

    expect(segunda.status).toBe(STATUS_DEDUPLICADO);
    expect(doTipo('set-user')).toHaveLength(1);
  });

  /**
   * `queued` e lido ANTES de `enfileirar`, em `chamadaDeDados`, e o adiamento do 5.19 acontece
   * DEPOIS — dentro do despacho. Um nao pode comer o outro: a chamada que esperou o boot continua
   * dizendo que esperou, mesmo com o provedor adiando o despacho mais um tick.
   */
  it('chamada antes do boot com provedor assincrono continua resolvendo como ENFILEIRADA', async () => {
    window.$chatwoot.setIdentityTokenProvider(() =>
      Promise.resolve('jwt.assincrono')
    );

    const promessa = window.$chatwoot.setUser('CRM-1', { name: 'Ana' });
    await drenar();
    const r = await promessa;

    expect(r.status).toBe(STATUS_ENFILEIRADO);
    expect(r.queued).toBe(true);
    expect(doTipo('set-user')[0].value.user.identity_token).toBe(
      'jwt.assincrono'
    );
  });

  /**
   * `updateUser` NAO deduplica de proposito (5.17), e o 5.19 tambem o envolveu em `comCredencial`.
   * O retorno da callback ali e `undefined`, e isso tem de continuar significando "aceito" — nao
   * "deduplicado" — depois de atravessar a promessa do provedor.
   */
  it('updateUser com provedor assincrono resolve como ACEITO nas duas chamadas iguais', async () => {
    window.$chatwoot.setIdentityTokenProvider(() =>
      Promise.resolve('jwt.assincrono')
    );
    await drenar();

    const primeira = await window.$chatwoot.updateUser('CRM-1', {
      name: 'Ana',
    });
    const segunda = await window.$chatwoot.updateUser('CRM-1', { name: 'Ana' });

    expect(primeira.status).toBe(STATUS_ACEITO);
    expect(segunda.status).toBe(STATUS_ACEITO);
    expect(doTipo('update-user')).toHaveLength(2);
    expect(doTipo('update-user')[1].value.user.identity_token).toBe(
      'jwt.assincrono'
    );
  });

  /**
   * O `identity_token` NAO pode vazar para `window.$chatwoot.user` — regra RC5 do 5.19 — e isso
   * continua valendo no caminho adiado, que e o unico em que o objeto com a credencial existe
   * separado por mais de um tick.
   */
  it('nem no caminho adiado a credencial encosta em window.$chatwoot.user', async () => {
    window.$chatwoot.setIdentityTokenProvider(() =>
      Promise.resolve('jwt.assincrono')
    );
    await drenar();

    await window.$chatwoot.setUser('CRM-1', { name: 'Ana' });

    expect(window.$chatwoot.user.identity_token).toBeUndefined();
    expect(window.$chatwoot.getUser().identity_token).toBeUndefined();
    expect(doTipo('set-user')[0].value.user.identity_token).toBe(
      'jwt.assincrono'
    );
  });
});

/**
 * A SEGUNDA COSTURA, no outro arquivo que os dois blocos disputaram.
 *
 * `buildContactPayload` recebeu um `if` de cada lado, no MESMO ponto: `clear_attributes` (5.17,
 * a lista de campos que o verbo `set` quer apagar) e `identity_token` (5.19, a credencial). Cada
 * suite exercitou o seu isolado; ninguem montou o payload que a producao monta o tempo todo, que
 * e o dos DOIS ao mesmo tempo — todo `setUser` de site com credencial e um `merge: false` com
 * campo de topo omitido E token presente.
 *
 * O que se mede aqui e a disjuncao: `clear_attributes` so olha `TOP_LEVEL_KEYS`, entao a
 * credencial nao pode aparecer na lista de apagamento. Colocar `identity_token` no `TOP_LEVEL_KEYS`
 * por engano — e ele e um campo de topo do payload, entao o engano e plausivel — faria todo
 * `setUser` sem credencial mandar "apague o identity_token" para o servidor.
 */
describe('reconciliacao 5.17 + 5.19 — os dois `if` no mesmo payload', () => {
  it('o `set` com credencial emite as DUAS coisas, e a credencial nao entra na lista de apagamento', async () => {
    const { buildContactPayload } = await import(
      '../../widget/helpers/identityPayload'
    );

    const payload = buildContactPayload(
      { name: 'Ana', identity_token: 'jwt.de.verdade' },
      { merge: false }
    );

    expect(payload.identity_token).toBe('jwt.de.verdade');
    expect(payload.clear_attributes).toContain('email');
    expect(payload.clear_attributes).not.toContain('identity_token');
  });

  it('o `update` com credencial leva a credencial e NAO leva lista de apagamento', async () => {
    const { buildContactPayload } = await import(
      '../../widget/helpers/identityPayload'
    );

    const payload = buildContactPayload(
      { name: 'Ana', identity_token: 'jwt.de.verdade' },
      { merge: true }
    );

    expect(payload.identity_token).toBe('jwt.de.verdade');
    expect('clear_attributes' in payload).toBe(false);
  });
});
