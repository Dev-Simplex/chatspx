import fs from 'fs';
import path from 'path';
import {
  APPEARANCE_OVERRIDES_PATH,
  buildAppearanceOverridesRequest,
} from 'widget/api/appearanceOverridesRequest';

/**
 * Bloco 3.18 — o montador da requisicao, medido sozinho.
 *
 * Este modulo e a UNICA fonte da URL e do corpo do relatorio de precedencia, e e ele que o
 * request spec `spec/controllers/api/v1/widget/appearance_overrides_request_spec.rb` executa no
 * `node` para mandar ao Rails de verdade. Ou seja: o que estiver verde aqui e exatamente o que
 * atravessa a junta la — nao ha uma segunda copia escrita a mao para as duas divergirem.
 */
describe('3.18 — a requisicao do relatorio de precedencia', () => {
  const TOKEN = 'aBcD1234websiteToken';
  const search = `?website_token=${TOKEN}&cw_conversation=cookie-de-sessao`;

  it('leva o `website_token`, que e o que o `set_web_widget` exige', () => {
    const requisicao = buildAppearanceOverridesRequest({
      search,
      fields: ['theme', 'position'],
    });

    expect(requisicao.url).toBe(
      `${APPEARANCE_OVERRIDES_PATH}?website_token=${TOKEN}`
    );
    expect(requisicao.body).toEqual({ fields: ['theme', 'position'] });
  });

  it('a lista VAZIA e uma medicao e vira requisicao', () => {
    expect(buildAppearanceOverridesRequest({ search, fields: [] })).toEqual({
      url: `${APPEARANCE_OVERRIDES_PATH}?website_token=${TOKEN}`,
      body: { fields: [] },
    });
  });

  it('nao manda o `cw_conversation` junto — credencial de sessao nao viaja em URL que ninguem le', () => {
    const { url } = buildAppearanceOverridesRequest({
      search,
      fields: ['position'],
    });

    expect(url).not.toContain('cw_conversation');
  });

  it('escapa o token: ele vira query string, e nao ha token confiavel', () => {
    const { url } = buildAppearanceOverridesRequest({
      search: '?website_token=a%26b%3Dc',
      fields: ['position'],
    });

    expect(url).toBe(`${APPEARANCE_OVERRIDES_PATH}?website_token=a%26b%3Dc`);
  });

  describe('quando NAO ha o que mandar', () => {
    it('sem `website_token` no `search` devolve null — 404 nao vira ida a rede', () => {
      expect(
        buildAppearanceOverridesRequest({
          search: '?cw_conversation=so-o-cookie',
          fields: ['position'],
        })
      ).toBeNull();
      expect(
        buildAppearanceOverridesRequest({ search: '', fields: ['position'] })
      ).toBeNull();
      expect(
        buildAppearanceOverridesRequest({ fields: ['position'] })
      ).toBeNull();
    });

    it('`fields` que nao e array devolve null — ausencia nao e lista vazia', () => {
      expect(buildAppearanceOverridesRequest({ search })).toBeNull();
      expect(
        buildAppearanceOverridesRequest({ search, fields: null })
      ).toBeNull();
      expect(
        buildAppearanceOverridesRequest({ search, fields: 'position' })
      ).toBeNull();
      expect(buildAppearanceOverridesRequest()).toBeNull();
    });
  });

  it('nao importa nada — e por isso que o request spec consegue executa-lo', () => {
    // Nao e estilo: `spec/controllers/api/v1/widget/appearance_overrides_request_spec.rb` copia
    // esta fonte para um `.mjs` e a roda no `node`, sem bundler e sem `node_modules`. Um `import`
    // aqui quebra aquele spec — e com ele a unica medicao que atravessa a junta de verdade. Esta
    // assercao faz a queda acontecer NESTE arquivo, onde a causa esta escrita.
    const fonte = fs.readFileSync(
      path.resolve(
        process.cwd(),
        'app/javascript/widget/api/appearanceOverridesRequest.js'
      ),
      'utf8'
    );
    const linhasDeCodigo = fonte
      .split('\n')
      .filter(linha => !linha.trim().startsWith('*'));

    expect(linhasDeCodigo.join('\n')).not.toMatch(/^\s*import\s/m);
  });
});
