import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  setIdentityTokenProvider,
  resolveIdentityToken,
  resetarProvedorParaTestes,
} from '../identityToken';

/**
 * Bloco 5.19 — `identityTokenProvider`, o produtor do JWT no cliente.
 *
 * O diagnostico que abriu esta frente foi medido, nao suposto: `grep identity_token` em
 * `app/javascript/` devolvia ZERO. O servidor validava um formato que nenhuma linha do produto
 * conseguia produzir.
 *
 * Os exemplos abaixo cobrem as duas metades disso, nesta ordem: o registro do callback (unidade)
 * e o REPASSE ate a mensagem que sai do host (integracao pelo entrypoint real do SDK).
 */
describe('5.19 — o registro do provedor', () => {
  beforeEach(() => resetarProvedorParaTestes());

  it('sem provedor registrado nao ha credencial, e isso nao e erro', async () => {
    const aoFalhar = vi.fn();

    expect(await resolveIdentityToken(aoFalhar)).toBeUndefined();
    expect(aoFalhar).not.toHaveBeenCalled();
  });

  it('provedor sincrono devolve o token', async () => {
    setIdentityTokenProvider(() => 'jwt.sincrono');

    expect(await resolveIdentityToken()).toBe('jwt.sincrono');
  });

  it('provedor assincrono tambem — quem integra nao precisa saber qual dos dois escrevemos', async () => {
    setIdentityTokenProvider(async () => 'jwt.assincrono');

    expect(await resolveIdentityToken()).toBe('jwt.assincrono');
  });

  it('e chamado A CADA identificacao, porque quem decide validade e o `exp`', async () => {
    const provedor = vi
      .fn()
      .mockResolvedValueOnce('jwt.primeiro')
      .mockResolvedValueOnce('jwt.renovado');
    setIdentityTokenProvider(provedor);

    expect(await resolveIdentityToken()).toBe('jwt.primeiro');
    expect(await resolveIdentityToken()).toBe('jwt.renovado');
    expect(provedor).toHaveBeenCalledTimes(2);
  });

  // A GARANTIA 1 DO 1.23, aplicada a credencial: um provedor que estoura nao pode derrubar a
  // identificacao. O aceite do bloco diz que token invalido degrada para anonimo, e nao para
  // erro; a falha do provedor e o mesmo caso, do lado de ca.
  it('provedor que LANCA degrada para anonimo e reporta — nao propaga', async () => {
    const aoFalhar = vi.fn();
    setIdentityTokenProvider(() => {
      throw new Error('backend do cliente fora do ar');
    });

    expect(await resolveIdentityToken(aoFalhar)).toBeUndefined();
    expect(aoFalhar).toHaveBeenCalledTimes(1);
    expect(aoFalhar.mock.calls[0][0].message).toBe(
      'backend do cliente fora do ar'
    );
  });

  it('promessa REJEITADA tem o mesmo destino da excecao sincrona', async () => {
    const aoFalhar = vi.fn();
    setIdentityTokenProvider(() => Promise.reject(new Error('401 no /token')));

    expect(await resolveIdentityToken(aoFalhar)).toBeUndefined();
    expect(aoFalhar).toHaveBeenCalledTimes(1);
  });

  it('devolver nada e resposta legitima (visitante deslogado), e NAO vira erro', async () => {
    const aoFalhar = vi.fn();
    setIdentityTokenProvider(() => undefined);
    expect(await resolveIdentityToken(aoFalhar)).toBeUndefined();

    setIdentityTokenProvider(() => '');
    expect(await resolveIdentityToken(aoFalhar)).toBeUndefined();

    expect(aoFalhar).not.toHaveBeenCalled();
  });

  // Forma errada E engano de quem integra, e sobre isso o SDK nao pode ser mudo: um
  // `{ token: '...' }` devolvido por engano viraria `[object Object]` no corpo da requisicao.
  it('forma errada nao vira token, e o integrador fica sabendo', async () => {
    const aoFalhar = vi.fn();
    setIdentityTokenProvider(() => ({ token: 'jwt.dentro.de.objeto' }));

    expect(await resolveIdentityToken(aoFalhar)).toBeUndefined();
    expect(aoFalhar).toHaveBeenCalledTimes(1);
    expect(aoFalhar.mock.calls[0][0].message).toMatch(/string/);
  });

  it('registrar algo que nao e funcao DESREGISTRA, em vez de guardar lixo', async () => {
    setIdentityTokenProvider(() => 'jwt.velho');
    setIdentityTokenProvider(null);

    expect(await resolveIdentityToken()).toBeUndefined();
  });

  // ── A RESPOSTA PRONTA NAO PODE VIRAR PROMESSA ────────────────────────────────────────────
  //
  // Isto nao e microotimizacao: a fila pre-boot do 1.23 preserva a ordem de chegada porque cada
  // despacho emite a sua mensagem no MESMO tick em que e chamado. Escrever `resolveIdentityToken`
  // como `async` fez o `set-user` sair DEPOIS dos seis metodos enfileirados atras dele — vermelho
  // medido em `preBootQueue.spec.js`, e defeito real: rotular um contato que ainda nao foi
  // identificado nao e o mesmo fato. `.then` aqui e a marca de que alguem transformou de novo o
  // caminho sincrono em assincrono.
  it('sem provedor, a resposta e SINCRONA — a ordem da fila do 1.23 depende disso', () => {
    expect(resolveIdentityToken()).toBeUndefined();
  });

  it('provedor sincrono responde no MESMO tick, sem promessa no meio', () => {
    setIdentityTokenProvider(() => 'jwt.sincrono');

    expect(resolveIdentityToken()).toBe('jwt.sincrono');
  });

  it('so o provedor assincrono adia, porque so ele precisa', () => {
    setIdentityTokenProvider(async () => 'jwt.assincrono');

    expect(typeof resolveIdentityToken().then).toBe('function');
  });
});

describe('5.19 — o repasse do token pela API publica do host', () => {
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

    // A ORDEM IMPORTA — mesma razao de `track.spec.js`: `resetModules` faz o entrypoint importar
    // uma instancia NOVA de `IFrameHelper`, e espionar a antiga nao intercepta nada.
    vi.resetModules();
    ({ IFrameHelper } = await import('../IFrameHelper'));
    vi.spyOn(IFrameHelper, 'sendMessage').mockImplementation((key, value) => {
      enviadas.push({ key, value });
    });

    await import('../../entrypoints/sdk.js');
    window.chatwootSDK.run({
      baseUrl: 'https://exemplo.test',
      websiteToken: 'tok-5-19',
    });
  }, 20000);

  afterEach(() => {
    vi.restoreAllMocks();
    document.cookie =
      'cw_user_tok-5-19=; expires=Thu, 01 Jan 1970 00:00:00 GMT';
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

  it('o metodo publico existe e aceita o callback', () => {
    expect(typeof window.$chatwoot.setIdentityTokenProvider).toBe('function');
  });

  it('setUser leva o identity_token junto do resto do usuario', async () => {
    window.$chatwoot.setIdentityTokenProvider(() => 'jwt.do.cliente');
    const promessa = window.$chatwoot.setUser('CRM-4711', {
      name: 'Ana',
      email: 'ana@exemplo.com.br',
    });
    await drenar();
    await promessa;

    expect(doTipo('set-user')).toHaveLength(1);
    expect(doTipo('set-user')[0].value.user.identity_token).toBe(
      'jwt.do.cliente'
    );
    expect(doTipo('set-user')[0].value.user.name).toBe('Ana');
  });

  it('updateUser, o verbo que mescla, leva a credencial pelo mesmo caminho', async () => {
    window.$chatwoot.setIdentityTokenProvider(async () => 'jwt.renovado');
    const promessa = window.$chatwoot.updateUser('CRM-4711', {
      phone_number: '+5511999998888',
    });
    await drenar();
    await promessa;

    expect(doTipo('update-user')).toHaveLength(1);
    expect(doTipo('update-user')[0].value.user.identity_token).toBe(
      'jwt.renovado'
    );
  });

  // A CONDICAO RUIM FORCADA — e esta e a assercao mais importante do arquivo.
  //
  // `window.$chatwoot` e legivel por QUALQUER script de terceiro da pagina (regra RC5). O
  // `identity_token` e credencial ao portador: guarda-lo ali, ou devolve-lo por `getUser()`,
  // entregaria a identidade do visitante a qualquer tag do GTM do cliente. Ele viaja na
  // mensagem para o iframe e para por ai.
  it('o token NAO fica em window.$chatwoot nem sai por getUser()', async () => {
    window.$chatwoot.setIdentityTokenProvider(() => 'jwt.secreto');
    const promessa = window.$chatwoot.setUser('CRM-4711', { name: 'Ana' });
    await drenar();
    await promessa;

    expect(doTipo('set-user')[0].value.user.identity_token).toBe('jwt.secreto');
    expect(window.$chatwoot.user.identity_token).toBeUndefined();
    expect(window.$chatwoot.getUser().identity_token).toBeUndefined();
    expect(JSON.stringify(window.$chatwoot)).not.toContain('jwt.secreto');
  });

  // O par de integracao das tres assercoes de sincronia acima: a ordem da fila do 1.23 medida
  // ponta a ponta, com um provedor registrado. Foi assim que a primeira versao desta frente foi
  // pega — `set-user` saia por ultimo.
  it('com provedor sincrono, o set-user continua saindo ANTES do que veio depois dele', async () => {
    window.$chatwoot.setIdentityTokenProvider(() => 'jwt.sincrono');
    window.$chatwoot.setUser('CRM-4711', { name: 'Ana' });
    window.$chatwoot.setLabel('vip');
    await drenar();

    expect(enviadas.map(m => m.key).filter(k => k !== 'config-set')).toEqual(
      expect.arrayContaining(['set-user', 'set-label'])
    );
    const ordem = enviadas.map(m => m.key);
    expect(ordem.indexOf('set-user')).toBeLessThan(ordem.indexOf('set-label'));
  });

  it('sem provedor, a mensagem sai exatamente como antes deste bloco', async () => {
    const promessa = window.$chatwoot.setUser('CRM-4711', { name: 'Ana' });
    await drenar();
    await promessa;

    expect(doTipo('set-user')).toHaveLength(1);
    expect('identity_token' in doTipo('set-user')[0].value.user).toBe(false);
  });

  // A RE-HIDRATACAO (`IFrameHelper.events.loaded`) e o caminho do iframe recriado — `reset()`, ou
  // uma navegacao que recria o frame — com o SDK ja identificado e nada na fila. Ali quem manda o
  // `set-user` nao e o site: e o proprio SDK, a partir de `window.$chatwoot.user`. E o `window`
  // nao guarda a credencial, de proposito — entao a credencial tem de ser pedida de novo ao
  // provedor, ou a sessao renasce identificada e NAO verificada.
  it('a re-hidratacao do iframe recriado pede a credencial de novo', async () => {
    window.$chatwoot.setIdentityTokenProvider(() => 'jwt.rehidratado');
    window.$chatwoot.identifier = 'CRM-4711';
    window.$chatwoot.user = { name: 'Ana' };

    await drenar();
    await Promise.resolve();
    await Promise.resolve();

    expect(doTipo('set-user')).toHaveLength(1);
    expect(doTipo('set-user')[0].value.user).toEqual({
      name: 'Ana',
      identity_token: 'jwt.rehidratado',
    });
    // e o `window` continua sem a credencial depois da re-hidratacao
    expect(window.$chatwoot.user.identity_token).toBeUndefined();
  });

  // ── O COOKIE DE DEDUPE, E A RAZAO DE ELE OLHAR A PRESENCA E NAO O VALOR ───────────────────
  //
  // Os dois exemplos abaixo sao as duas metades da mesma decisao, e cada um refuta uma
  // implementacao mais obvia: pelo VALOR (o token entra no hash) e IGNORANDO (o token fica fora).
  it('token renovado com os MESMOS dados nao reenvia — o valor do JWT nao entra no hash', async () => {
    // Pelo valor, este exemplo falharia: o `exp` muda a cada emissao, entao todo visitante ja
    // identificado mandaria um `setUser` por carregamento de pagina — exatamente a chamada que o
    // cookie de dedupe existe para evitar.
    let n = 0;
    window.$chatwoot.setIdentityTokenProvider(() => {
      n += 1;
      return `jwt.emissao.${n}`;
    });

    const primeira = window.$chatwoot.setUser('CRM-4711', { name: 'Ana' });
    await drenar();
    await primeira;
    await window.$chatwoot.setUser('CRM-4711', { name: 'Ana' });

    expect(doTipo('set-user')).toHaveLength(1);
  });

  it('anonimo primeiro e credenciado depois REENVIA — a presenca entra no hash', async () => {
    // Ignorando o token, este exemplo falharia, e o defeito seria de identidade: o provedor
    // falha numa carga (backend do cliente fora do ar), o cookie e gravado, e a carga seguinte
    // — ja com o token bom — seria cortada pelo dedupe. A sessao nunca ficaria `hmac_verified`,
    // e nada no console diria por que.
    const primeira = window.$chatwoot.setUser('CRM-4711', { name: 'Ana' });
    await drenar();
    await primeira;

    window.$chatwoot.setIdentityTokenProvider(() => 'jwt.depois.da.falha');
    await window.$chatwoot.setUser('CRM-4711', { name: 'Ana' });

    const enviados = doTipo('set-user');
    expect(enviados).toHaveLength(2);
    expect(enviados[0].value.user.identity_token).toBeUndefined();
    expect(enviados[1].value.user.identity_token).toBe('jwt.depois.da.falha');
  });

  it('provedor que estoura nao impede a identificacao — ela sai anonima de credencial', async () => {
    window.$chatwoot.setIdentityTokenProvider(() => {
      throw new Error('backend do cliente fora do ar');
    });
    const promessa = window.$chatwoot.setUser('CRM-4711', { name: 'Ana' });
    await drenar();
    await promessa;

    expect(doTipo('set-user')).toHaveLength(1);
    expect(doTipo('set-user')[0].value.user.identity_token).toBeUndefined();
    expect(doTipo('set-user')[0].value.identifier).toBe('CRM-4711');
  });
});
