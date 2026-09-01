import fs from 'fs';
import path from 'path';
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

  /**
   * A VIA DOCUMENTADA — a metade do aceite que nenhuma asserção sobre o código alcança.
   *
   * Uma via de configuração que só existe no código é uma via que ninguém usa: o integrador não
   * adivinha nome de atributo. E documento que promete uma recusa que o produto não faz é pior
   * do que documento nenhum — ele convida a pessoa a colar a credencial dela no HTML e ficar
   * tranquila. Estes exemplos cruzam o guia com as DUAS listas deste arquivo.
   */
  describe('a via documentada', () => {
    const guia = fs.readFileSync(
      path.resolve(process.cwd(), 'docs/tracking/guia-de-integracao.md'),
      'utf8'
    );

    // `data-launcher-title` → `launcherTitle`: é a conversão que o navegador faz ao montar o
    // `dataset`, e é a que o guia ensina.
    const paraChave = atributo =>
      atributo
        .replace(/^data-/, '')
        .replace(/-([a-z0-9])/g, (_, letra) => letra.toUpperCase());

    const atributosDoGuia = [
      ...new Set(
        [...guia.matchAll(/`?(data-[a-z0-9-]+)`?/g)].map(([, nome]) => nome)
      ),
    ].filter(nome => nome !== 'data-chatspx-snippet');

    it('o guia ensina a via, com o marcador que o servidor realmente escreve', () => {
      const webWidget = fs.readFileSync(
        path.resolve(process.cwd(), 'app/models/channel/web_widget.rb'),
        'utf8'
      );

      expect(guia).toContain('data-chatspx-snippet');
      expect(webWidget).toContain('<script data-chatspx-snippet>');
      expect(guia).toMatch(/precedência/i);
    });

    it('nomeia atributos de verdade — não é um parágrafo genérico', () => {
      expect(atributosDoGuia.length).toBeGreaterThan(4);
    });

    it('todo `data-*` que ele apresenta como CONFIGURAÇÃO está na allowlist', () => {
      const configDoGuia = atributosDoGuia
        .map(paraChave)
        .filter(chave => !isIdentityKey(chave) && !isSecretKey(chave));

      expect(configDoGuia.length).toBeGreaterThan(2);
      configDoGuia.forEach(chave =>
        expect({ chave, aceita: CONFIG_KEYS.includes(chave) }).toEqual({
          chave,
          aceita: true,
        })
      );
    });

    it('todo `data-*` que ele promete recusar É recusado de fato', () => {
      const recusadosNoGuia = atributosDoGuia
        .map(paraChave)
        .filter(chave => !CONFIG_KEYS.includes(chave));

      expect(recusadosNoGuia.length).toBeGreaterThan(2);
      recusadosNoGuia.forEach(chave => {
        const { config, rejected } = readSnippetConfig({ [chave]: 'x' });

        expect({ chave, config, rejected }).toEqual({
          chave,
          config: {},
          rejected: [chave],
        });
      });
    });

    it('manda a identidade para a API JS, com o nome do método que existe', () => {
      const sdk = fs.readFileSync(
        path.resolve(process.cwd(), 'app/javascript/entrypoints/sdk.js'),
        'utf8'
      );

      expect(guia).toContain('setUser');
      expect(/\n {4}setUser\(/.test(sdk)).toBe(true);
      expect(guia).toContain('updateUser');
      expect(/\n {4}updateUser\(/.test(sdk)).toBe(true);
      expect(IDENTITY_KEYS).toContain('identifierhash');
    });
  });
});
