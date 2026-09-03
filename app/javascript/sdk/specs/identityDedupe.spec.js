import {
  getUserString,
  hasUserKeys,
  computeHashForUserData,
} from '../cookieHelpers';

// Bloco 5.17 — o dedupe do setUser.
//
// O defeito: `getUserString` so considerava avatar_url, email, name e identifier_hash. Mudar so o
// telefone produzia o MESMO hash, o SDK comparava com o cookie e retornava cedo — a atualizacao
// nao saia do navegador. E `hasUserKeys` exigia um daqueles tres, entao telefone sozinho nem
// chegava a ser tentado.
describe('5.17 — o telefone participa da identidade', () => {
  const base = {
    name: 'Ana',
    email: 'ana@exemplo.com.br',
    avatar_url: 'https://exemplo.com.br/ana.png',
  };

  describe('hasUserKeys — quem identifica sozinho', () => {
    it('phone_number sozinho identifica', () => {
      expect(hasUserKeys({ phone_number: '+5511999998888' })).toBe(true);
    });

    it('os campos que ja identificavam continuam identificando', () => {
      expect(hasUserKeys({ email: 'ana@exemplo.com.br' })).toBe(true);
      expect(hasUserKeys({ name: 'Ana' })).toBe(true);
      expect(hasUserKeys({ avatar_url: 'https://x/y.png' })).toBe(true);
    });

    it('objeto sem nenhum campo de identidade continua sendo recusado', () => {
      expect(hasUserKeys({})).toBe(false);
      expect(hasUserKeys({ city: 'Curitiba' })).toBe(false);
    });
  });

  describe('o hash de dedupe cobre o que o widget realmente envia', () => {
    it('mudar SO o telefone muda o hash — senao a atualizacao nao sai do navegador', () => {
      const antes = computeHashForUserData({
        identifier: 'u-1',
        user: { ...base, phone_number: '+5511999998888' },
      });
      const depois = computeHashForUserData({
        identifier: 'u-1',
        user: { ...base, phone_number: '+5511777776666' },
      });

      expect(depois).not.toBe(antes);
    });

    it.each([
      ['company_name', 'Simplex'],
      ['city', 'Curitiba'],
      ['country_code', 'BR'],
      ['description', 'cliente desde 2019'],
      ['signed_up_at', '2026-08-18T00:00:00Z'],
    ])('mudar so %s tambem muda o hash', (campo, valor) => {
      const antes = computeHashForUserData({ identifier: 'u-1', user: base });
      const depois = computeHashForUserData({
        identifier: 'u-1',
        user: { ...base, [campo]: valor },
      });

      expect(depois).not.toBe(antes);
    });

    it('mudar custom_attributes muda o hash', () => {
      const antes = computeHashForUserData({
        identifier: 'u-1',
        user: { ...base, custom_attributes: { plano: 'pro' } },
      });
      const depois = computeHashForUserData({
        identifier: 'u-1',
        user: { ...base, custom_attributes: { plano: 'enterprise' } },
      });

      expect(depois).not.toBe(antes);
    });

    it('chamar duas vezes com o MESMO objeto mantem o hash — o dedupe continua deduplicando', () => {
      const user = { ...base, phone_number: '+5511999998888' };

      expect(computeHashForUserData({ identifier: 'u-1', user })).toBe(
        computeHashForUserData({ identifier: 'u-1', user })
      );
    });

    it('a ordem das chaves do objeto nao altera o hash', () => {
      const a = computeHashForUserData({
        identifier: 'u-1',
        user: { name: 'Ana', phone_number: '+551199', email: 'a@b.c' },
      });
      const b = computeHashForUserData({
        identifier: 'u-1',
        user: { email: 'a@b.c', phone_number: '+551199', name: 'Ana' },
      });

      expect(a).toBe(b);
    });

    it('identificadores diferentes nunca colidem', () => {
      const user = { ...base, phone_number: '+5511999998888' };

      expect(computeHashForUserData({ identifier: 'u-1', user })).not.toBe(
        computeHashForUserData({ identifier: 'u-2', user })
      );
    });
  });

  describe('getUserString', () => {
    it('inclui o telefone na string que vira hash', () => {
      const texto = getUserString({
        identifier: 'u-1',
        user: { ...base, phone_number: '+5511999998888' },
      });

      expect(texto).toContain('+5511999998888');
    });
  });
});
