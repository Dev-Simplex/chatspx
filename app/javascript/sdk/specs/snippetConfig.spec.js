import {
  CONFIG_KEYS,
  IDENTITY_KEYS,
  isIdentityKey,
  isSecretKey,
  readSnippetConfig,
  mergeSnippetConfig,
} from '../snippetConfig';

// Bloco 5.18 — configuração viaja por qualquer via; identidade e credencial, só pela API JS.
describe('5.18 — data-* de configuração no snippet', () => {
  describe('configuração viaja', () => {
    it('lê as chaves de configuração do dataset', () => {
      const { config } = readSnippetConfig({
        position: 'left',
        locale: 'pt_BR',
        launcherTitle: 'Fale conosco',
      });

      expect(config).toEqual({
        position: 'left',
        locale: 'pt_BR',
        launcherTitle: 'Fale conosco',
      });
    });

    it('converte booleano de string, senão data-hide-message-bubble="false" seria verdadeiro', () => {
      const { config } = readSnippetConfig({
        hideMessageBubble: 'false',
        showPopoutButton: 'true',
      });

      expect(config.hideMessageBubble).toBe(false);
      expect(config.showPopoutButton).toBe(true);
    });

    it('chave de configuração desconhecida é ignorada, sem virar config', () => {
      const { config, rejected } = readSnippetConfig({ inventada: 'x' });

      expect(config).toEqual({});
      expect(rejected).toEqual([]);
    });
  });

  describe('ASSERÇÃO NEGATIVA — identidade NUNCA entra', () => {
    it.each(IDENTITY_KEYS)('recusa a chave de identidade %s', chave => {
      const { config, rejected } = readSnippetConfig({ [chave]: 'valor' });

      expect(config).toEqual({});
      expect(rejected).toEqual([chave]);
    });

    it('recusa em qualquer grafia: identifierHash, identifier_hash, IDENTIFIERHASH', () => {
      ['identifierHash', 'identifier_hash', 'IDENTIFIERHASH'].forEach(chave => {
        expect(isIdentityKey(chave)).toBe(true);
      });
    });

    it('nenhuma chave de identidade está na lista de configuração', () => {
      const intersecao = CONFIG_KEYS.filter(chave => isIdentityKey(chave));

      expect(intersecao).toEqual([]);
    });

    it('identidade misturada com configuração: a config passa, a identidade NÃO', () => {
      const { config, rejected } = readSnippetConfig({
        position: 'left',
        email: 'ana@exemplo.com.br',
        identifierHash: 'abc123',
      });

      expect(config).toEqual({ position: 'left' });
      expect(Object.values(config)).not.toContain('ana@exemplo.com.br');
      expect(rejected).toEqual(['email', 'identifierHash']);
    });
  });

  describe('ASSERÇÃO NEGATIVA — credencial NUNCA entra', () => {
    it.each([
      'accessToken',
      'apiKey',
      'clientSecret',
      'password',
      'privateKey',
      'authorization',
      'bearerToken',
      'webhookSecret',
    ])('recusa %s', chave => {
      expect(isSecretKey(chave)).toBe(true);

      const { config, rejected } = readSnippetConfig({ [chave]: 'x' });
      expect(config).toEqual({});
      expect(rejected).toEqual([chave]);
    });

    it('nenhuma chave de configuração é confundida com credencial', () => {
      const falsosPositivos = CONFIG_KEYS.filter(chave => isSecretKey(chave));

      expect(falsosPositivos).toEqual([]);
    });
  });

  describe('precedência declarada', () => {
    it('window.chatwootSettings VENCE o data-* do snippet', () => {
      const { settings } = mergeSnippetConfig(
        { position: 'right' },
        { position: 'left', locale: 'pt_BR' }
      );

      expect(settings.position).toBe('right');
      expect(settings.locale).toBe('pt_BR');
    });

    it('sem chatwootSettings, o data-* configura sozinho', () => {
      const { settings } = mergeSnippetConfig({}, { position: 'left' });

      expect(settings.position).toBe('left');
    });

    it('a recusa é devolvida ao chamador para virar aviso no console', () => {
      const { settings, rejected } = mergeSnippetConfig(
        {},
        { email: 'ana@exemplo.com.br', accessToken: 'EAAG' }
      );

      expect(settings).toEqual({});
      expect(rejected).toEqual(['email', 'accessToken']);
    });
  });
});
