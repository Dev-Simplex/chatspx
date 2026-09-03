/**
 * Bloco 5.08 — a segunda metade do coletor: o que roda quando o chat abre.
 *
 * Cobre T-C2.3 (`_fbc`/`_gcl_aw` no formato oficial, e a proibição de fabricar sem clique
 * real), T-C2.4 (allowlist de cookies) e T-C2.5 (timeout de 1 s no gtag).
 */
import {
  deriveFbc,
  deriveGclAw,
  clickIdentifiers,
  TTL_MS,
  subdomainIndex,
} from '../clickIds';
import { allowedCookies, gaSessionCookieName } from '../cookies';
import {
  googleIds,
  clientIdFromGaCookie,
  sessionIdFromGaCookie,
} from '../googleIds';
import { originAttributes } from '../index';
import { captureOrigin } from '../capture';

const AGORA = 1_760_000_000_000;

describe('5.08 — `_fbc` e `_gcl_aw` (T-C2.3)', () => {
  it('deriva `_fbc` no formato oficial fb.{subdomainIndex}.{timestamp}.{fbclid}', () => {
    const fbc = deriveFbc({
      fbclid: 'IwAR123',
      timestamp: AGORA,
      host: 'exemplo.com',
      now: AGORA,
    });

    expect(fbc).toBe(`fb.1.${AGORA}.IwAR123`);
  });

  it('deriva `_gcl_aw` no formato GCL.{unix em SEGUNDOS}.{gclid}', () => {
    expect(deriveGclAw({ gclid: 'Cj0KC', timestamp: AGORA, now: AGORA })).toBe(
      `GCL.${AGORA / 1000}.Cj0KC`
    );
  });

  it('NUNCA fabrica `_fbc` sem `fbclid` real — nem com timestamp e host válidos', () => {
    expect(
      deriveFbc({
        fbclid: undefined,
        timestamp: AGORA,
        host: 'exemplo.com',
        now: AGORA,
      })
    ).toBeNull();
    expect(
      deriveFbc({
        fbclid: '',
        timestamp: AGORA,
        host: 'exemplo.com',
        now: AGORA,
      })
    ).toBeNull();
  });

  it('não deriva depois da janela de 90 dias', () => {
    const vencido = AGORA - TTL_MS - 1;

    expect(
      deriveFbc({ fbclid: 'x', timestamp: vencido, host: 'a.com', now: AGORA })
    ).toBeNull();
    expect(
      deriveGclAw({ gclid: 'x', timestamp: vencido, now: AGORA })
    ).toBeNull();
  });

  it('conta o subdomainIndex a partir do TLD', () => {
    expect(subdomainIndex('com')).toBe(0);
    expect(subdomainIndex('exemplo.com')).toBe(1);
    expect(subdomainIndex('www.exemplo.com')).toBe(2);
  });

  it('o COOKIE REAL tem precedência sobre a derivação — quem escreveu conhece o domínio', () => {
    const saida = clickIdentifiers({
      touch: { fbclid: 'IwAR123', gclid: 'Cj0KC', ts: AGORA },
      cookies: {
        _fbc: 'fb.1.111.doPixel',
        _gcl_aw: 'GCL.222.doGtag',
        _fbp: 'fb.1.333.444',
      },
      host: 'exemplo.com',
      now: AGORA,
    });

    expect(saida.fbc).toBe('fb.1.111.doPixel');
    expect(saida.gcl_aw).toBe('GCL.222.doGtag');
    expect(saida.fbp).toBe('fb.1.333.444');
  });
});

describe('5.08 — allowlist de cookies (T-C2.4)', () => {
  it('lê só o que está na lista, e devolve o resto de fora', () => {
    const cookies = allowedCookies(
      '_fbp=fb.1.2.3; _ga=GA1.1.99.88; _ga_ABC123=GS1.1.777.1; sessao_do_cliente=segredo; carrinho=42'
    );

    expect(Object.keys(cookies).sort()).toEqual(['_fbp', '_ga', '_ga_ABC123']);
    expect(cookies.sessao_do_cliente).toBeUndefined();
  });

  it('não confunde `_ga_algo_do_site` com o cookie de sessão do GA4', () => {
    expect(Object.keys(allowedCookies('_ga_do_site=1'))).toEqual([]);
  });

  it('deriva o nome do cookie de sessão a partir do measurement id', () => {
    expect(gaSessionCookieName('G-ABC123')).toBe('_ga_ABC123');
    expect(gaSessionCookieName(null)).toBeNull();
  });

  it('não lança com cookie malformado', () => {
    expect(() => allowedCookies('=;;_fbp;_ga=')).not.toThrow();
  });
});

describe('5.08 — client_id e session_id com timeout de 1 s (T-C2.5)', () => {
  afterEach(() => {
    delete window.gtag;
    vi.useRealTimers();
  });

  it('usa a resposta do gtag quando ela chega', async () => {
    window.gtag = (_verbo, _id, campo, cb) =>
      cb(campo === 'client_id' ? '111.222' : '9988');

    const ids = await googleIds({ measurementId: 'G-ABC123', cookies: {} });

    expect(ids).toEqual({ ga_client_id: '111.222', ga_session_id: '9988' });
  });

  it('DESISTE em 1 s quando o gtag nunca chama o callback, e cai no cookie', async () => {
    vi.useFakeTimers();
    window.gtag = () => {}; // engole o callback: é o caso real do gtag ainda carregando

    const promessa = googleIds({
      measurementId: 'G-ABC123',
      cookies: {
        _ga: 'GA1.1.1234567890.1690000000',
        _ga_ABC123: 'GS1.1.555.1.1.0.0.0',
      },
    });
    await vi.advanceTimersByTimeAsync(1000);

    expect(await promessa).toEqual({
      ga_client_id: '1234567890.1690000000',
      ga_session_id: '555',
    });
  });

  it('não trava quando não há gtag nenhum na página', async () => {
    expect(await googleIds({ measurementId: 'G-ABC123', cookies: {} })).toEqual(
      {}
    );
  });

  it('não propaga exceção de um gtag quebrado', async () => {
    window.gtag = () => {
      throw new Error('container do GTM explodiu');
    };

    await expect(
      googleIds({ measurementId: 'G-ABC123', cookies: {} })
    ).resolves.toEqual({});
  });

  it('lê o client_id e o session_id do formato de cookie do GA4', () => {
    expect(clientIdFromGaCookie('GA1.1.1234567890.1690000000')).toBe(
      '1234567890.1690000000'
    );
    expect(clientIdFromGaCookie('lixo')).toBeNull();
    expect(sessionIdFromGaCookie('GS1.1.1690000000.1.1.1690000060.0.0.0')).toBe(
      '1690000000'
    );
  });
});

describe('5.08 — o payload que vira custom_attributes (T-C2.6)', () => {
  beforeEach(() => window.localStorage.clear());

  it('usa os prefixos `first_`/`last_` que o backend já conhece', async () => {
    captureOrigin({
      location: {
        search: '?utm_source=google&gclid=Cj0KC',
        host: 'loja.com.br',
        origin: 'https://loja.com.br',
        pathname: '/promo',
      },
      referrer: 'https://www.google.com/',
    });

    const attrs = await originAttributes({ host: 'loja.com.br' });

    expect(attrs.first_utm_source).toBe('google');
    expect(attrs.last_utm_source).toBe('google');
    expect(attrs.first_gclid).toBe('Cj0KC');
    expect(attrs.first_entry_referrer).toBe('https://www.google.com/');
    expect(attrs.first_landing_page).toBe('https://loja.com.br/promo');
    expect(attrs.gcl_aw).toMatch(/^GCL\.\d+\.Cj0KC$/);
  });

  it('devolve {} quando nunca houve toque — e não uma casca de chaves vazias', async () => {
    expect(await originAttributes()).toEqual({});
  });
});
