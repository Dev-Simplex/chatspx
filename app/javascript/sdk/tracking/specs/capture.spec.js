/**
 * Bloco 5.08 — ACEITE, primeira metade: *"visitante que chega por anúncio, navega 5 páginas
 * e só então abre o chat: a conversa nasce com o `first_utm_source` e o `gclid` certos"*.
 *
 * O que este spec mede é a REGRA que torna isso possível (T-C2.2): `first` write-once e
 * `last` que não é zerado por navegação interna. O erro clássico de mercado é o oposto —
 * cada página nova sobrescreve a origem com "referrer = o próprio site", e a campanha some
 * na segunda página.
 */
import { captureOrigin, storedOrigin } from '../capture';
import { STORE_KEY } from '../keys';

const ANUNCIO =
  '?utm_source=google&utm_medium=cpc&utm_campaign=black-friday&gclid=EAIaIQobCh';

const navegar = (path, { search = '', referrer = '' } = {}) =>
  captureOrigin({
    location: {
      search,
      host: 'loja.com.br',
      origin: 'https://loja.com.br',
      pathname: path,
    },
    referrer,
  });

describe('5.08 — captura de origem na landing page', () => {
  beforeEach(() => window.localStorage.clear());

  describe('a jornada do aceite: anúncio → 5 páginas → chat', () => {
    it('mantém a campanha e o gclid do PRIMEIRO toque depois de cinco páginas internas', () => {
      navegar('/promo', {
        search: ANUNCIO,
        referrer: 'https://www.google.com/',
      });
      navegar('/produtos', { referrer: 'https://loja.com.br/promo' });
      navegar('/produtos/42', { referrer: 'https://loja.com.br/produtos' });
      navegar('/carrinho', { referrer: 'https://loja.com.br/produtos/42' });
      navegar('/checkout', { referrer: 'https://loja.com.br/carrinho' });

      const { first, last } = storedOrigin();

      expect(first.utm_source).toBe('google');
      expect(first.utm_campaign).toBe('black-friday');
      expect(first.gclid).toBe('EAIaIQobCh');
      expect(first.landing_page).toBe('https://loja.com.br/promo');
      expect(first.entry_referrer).toBe('https://www.google.com/');
      // `last` também sobrevive: nenhuma das quatro páginas internas o tocou.
      expect(last.utm_source).toBe('google');
      expect(last.gclid).toBe('EAIaIQobCh');
    });

    it('navegação interna NÃO grava toque nenhum — é a regra que o mercado erra', () => {
      navegar('/promo', {
        search: ANUNCIO,
        referrer: 'https://www.google.com/',
      });
      const depoisDoAnuncio = JSON.stringify(storedOrigin());

      navegar('/produtos', { referrer: 'https://loja.com.br/promo' });

      expect(JSON.stringify(storedOrigin())).toBe(depoisDoAnuncio);
    });

    it('página sem parâmetro e sem referrer (digitou a URL) também não zera nada', () => {
      navegar('/promo', {
        search: ANUNCIO,
        referrer: 'https://www.google.com/',
      });

      navegar('/contato');

      expect(storedOrigin().last.utm_source).toBe('google');
    });
  });

  describe('first write-once vs last', () => {
    it('o PRIMEIRO toque nunca é reescrito, nem por uma campanha nova', () => {
      navegar('/promo', { search: '?utm_source=google&gclid=abc' });

      navegar('/oferta', { search: '?utm_source=meta&fbclid=xyz' });

      const { first, last } = storedOrigin();
      expect(first.utm_source).toBe('google');
      expect(first.gclid).toBe('abc');
      // ...e o ÚLTIMO é, porque é ele que responde "o que trouxe ESTA visita".
      expect(last.utm_source).toBe('meta');
      expect(last.fbclid).toBe('xyz');
      expect(last.gclid).toBeUndefined();
    });

    it('um referrer EXTERNO sem parâmetro nenhum também conta como toque novo', () => {
      navegar('/promo', {
        search: ANUNCIO,
        referrer: 'https://www.google.com/',
      });

      navegar('/blog', { referrer: 'https://news.ycombinator.com/' });

      const { first, last } = storedOrigin();
      expect(first.utm_source).toBe('google');
      expect(last.entry_referrer).toBe('https://news.ycombinator.com/');
      expect(last.utm_source).toBeUndefined();
    });

    it('grava a landing page da sessão, e não a página em que o chat abriu', () => {
      navegar('/promo', {
        search: ANUNCIO,
        referrer: 'https://www.google.com/',
      });
      navegar('/checkout', { referrer: 'https://loja.com.br/carrinho' });

      expect(storedOrigin().first.landing_page).toBe(
        'https://loja.com.br/promo'
      );
    });
  });

  describe('guardas', () => {
    it('trunca valor gigante em 255, como o backend', () => {
      navegar('/p', { search: `?utm_campaign=${'x'.repeat(900)}` });

      expect(storedOrigin().last.utm_campaign).toHaveLength(255);
    });

    it('não lança quando o localStorage está bloqueado (aba privada do Safari)', () => {
      const setItem = vi
        .spyOn(Storage.prototype, 'setItem')
        .mockImplementation(() => {
          throw new Error('QuotaExceededError');
        });

      expect(() => navegar('/p', { search: ANUNCIO })).not.toThrow();

      setItem.mockRestore();
    });

    it('não lança com o registro corrompido no storage', () => {
      window.localStorage.setItem(STORE_KEY, 'não é json');

      expect(() => navegar('/p', { search: ANUNCIO })).not.toThrow();
      expect(storedOrigin().last.utm_source).toBe('google');
    });

    it('ignora parâmetro que não está no vocabulário do backend', () => {
      navegar('/p', { search: '?utm_source=google&segredo=abc&ref=xyz' });

      const { last } = storedOrigin();
      expect(last.utm_source).toBe('google');
      expect(last.segredo).toBeUndefined();
      expect(last.ref).toBeUndefined();
    });
  });
});
