import Cookies from 'js-cookie';
import {
  getUserCookieName,
  getUserString,
  hasUserKeys,
  setCookieWithDomain,
} from '../cookieHelpers';

describe('#getUserCookieName', () => {
  it('returns correct cookie name', () => {
    global.$chatwoot = { websiteToken: '123456' };
    expect(getUserCookieName()).toBe('cw_user_123456');
  });
});

describe('#getUserString', () => {
  it('returns correct user string', () => {
    expect(
      getUserString({
        user: {
          name: 'Pranav',
          email: 'pranav@example.com',
          avatar_url: 'https://images.chatwoot.com/placeholder',
          identifier_hash: '12345',
        },
        identifier: '12345',
      })
    ).toBe(
      'avatar_urlhttps://images.chatwoot.com/placeholderemailpranav@example.comnamePranavidentifier_hash12345identifier12345'
    );

    expect(
      getUserString({
        user: {
          email: 'pranav@example.com',
          avatar_url: 'https://images.chatwoot.com/placeholder',
        },
      })
    ).toBe(
      'avatar_urlhttps://images.chatwoot.com/placeholderemailpranav@example.comnameidentifier_hashidentifier'
    );
  });
});

describe('#hasUserKeys', () => {
  it('checks whether the allowed list of keys are present', () => {
    expect(hasUserKeys({})).toBe(false);
    expect(hasUserKeys({ randomKey: 'randomValue' })).toBe(false);
    expect(hasUserKeys({ avatar_url: 'randomValue' })).toBe(true);
  });
});

// Mock the 'set' method of the 'Cookies' object

describe('setCookieWithDomain', () => {
  beforeEach(() => {
    vi.spyOn(Cookies, 'set');
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('should set a cookie with default parameters', () => {
    setCookieWithDomain('myCookie', 'cookieValue');

    expect(Cookies.set).toHaveBeenCalledWith('myCookie', 'cookieValue', {
      expires: 365,
      sameSite: 'Lax',
      domain: undefined,
      secure: false,
    });
  });

  it('should set a cookie with custom expiration and sameSite attribute', () => {
    setCookieWithDomain('myCookie', 'cookieValue', {
      expires: 30,
    });

    expect(Cookies.set).toHaveBeenCalledWith('myCookie', 'cookieValue', {
      expires: 30,
      sameSite: 'Lax',
      domain: undefined,
      secure: false,
    });
  });

  it('should set a cookie with a specific base domain', () => {
    setCookieWithDomain('myCookie', 'cookieValue', {
      baseDomain: 'example.com',
    });

    expect(Cookies.set).toHaveBeenCalledWith('myCookie', 'cookieValue', {
      expires: 365,
      sameSite: 'Lax',
      domain: 'example.com',
      secure: false,
    });
  });

  it('should stringify the cookie value when setting the value', () => {
    setCookieWithDomain(
      'myCookie',
      { value: 'cookieValue' },
      {
        baseDomain: 'example.com',
      }
    );

    expect(Cookies.set).toHaveBeenCalledWith(
      'myCookie',
      JSON.stringify({ value: 'cookieValue' }),
      {
        expires: 365,
        sameSite: 'Lax',
        domain: 'example.com',
        secure: false,
      }
    );
  });

  /**
   * Item 46 do gap analysis (P0), absorvido pelo bloco 4.19.
   *
   * O par de asserções é o ponto: `secure` liga em HTTPS E fica desligado em HTTP.
   * Só a primeira metade seria uma armadilha — cravar `secure: true` faria o
   * navegador DESCARTAR o cookie em todo site que ainda serve HTTP, e o widget
   * perderia a sessão do visitante sem um único erro no console.
   */
  it('marca `secure` quando a página é HTTPS, e NÃO marca em HTTP', () => {
    const localOriginal = Object.getOwnPropertyDescriptor(window, 'location');
    const comProtocolo = protocol => {
      Cookies.set.mockClear();
      // jsdom não deixa reatribuir `location`; redefinir a propriedade é o
      // caminho que o próprio jsdom documenta.
      Object.defineProperty(window, 'location', {
        value: { protocol },
        writable: true,
        configurable: true,
      });
      setCookieWithDomain('c', 'v', { baseDomain: 'example.com' });
      return Cookies.set.mock.calls[0][2].secure;
    };

    expect(comProtocolo('https:')).toBe(true);
    expect(comProtocolo('http:')).toBe(false);

    // Devolve a `location` do jsdom. Sem isto, todo arquivo que rodar depois
    // neste mesmo ambiente herda uma página fantasma — e o defeito aparece longe
    // daqui, num teste que não fala de cookie.
    Object.defineProperty(window, 'location', localOriginal);
  });

  it('should set a cookie with custom expiration, sameSite attribute, and specific base domain', () => {
    setCookieWithDomain('myCookie', 'cookieValue', {
      expires: 7,
      baseDomain: 'example.com',
    });

    expect(Cookies.set).toHaveBeenCalledWith('myCookie', 'cookieValue', {
      expires: 7,
      sameSite: 'Lax',
      domain: 'example.com',
      secure: false,
    });
  });
});
