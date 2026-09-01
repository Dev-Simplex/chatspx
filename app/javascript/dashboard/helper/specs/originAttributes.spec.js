import fs from 'fs';
import path from 'path';
import {
  CLICK_ID_KEYS,
  CONTACT_PREFIX,
  CONVERSATION_PREFIX,
  DERIVED_KEYS,
  ORIGIN_KINDS,
  UTM_KEYS,
  contactOriginKeys,
  conversationOriginKeys,
  hasSiteContext,
} from '../originAttributes';

/**
 * Bloco 5.23 — a guarda da duplicação.
 *
 * O painel precisa das chaves de origem no navegador; o catálogo canônico é Ruby. Este spec lê
 * `app/services/tracking/origin_attributes.rb` e exige que as listas batam — se alguém
 * acrescentar uma chave de um lado só, o CI diz qual.
 */
const ruby = fs.readFileSync(
  path.resolve(process.cwd(), 'app/services/tracking/origin_attributes.rb'),
  'utf8'
);

const listaDoRuby = nome =>
  new RegExp(`${nome} = %w\\[([^\\]]+)\\]`).exec(ruby)[1].trim().split(/\s+/);

describe('5.23 — o vocabulário de origem bate com o do servidor', () => {
  it('o arquivo Ruby foi mesmo lido', () => {
    expect(ruby).toContain('module Tracking::OriginAttributes');
  });

  it.each([
    ['UTM_KEYS', UTM_KEYS],
    ['CLICK_ID_KEYS', CLICK_ID_KEYS],
    ['DERIVED_KEYS', DERIVED_KEYS],
    ['ORIGIN_KINDS', ORIGIN_KINDS],
  ])('%s é igual à do servidor', (nome, doFront) => {
    expect(doFront).toEqual(listaDoRuby(nome));
  });

  it('os prefixos são os mesmos', () => {
    expect(ruby).toContain(`CONTACT_PREFIX = '${CONTACT_PREFIX}'`);
    expect(ruby).toContain(`CONVERSATION_PREFIX = '${CONVERSATION_PREFIX}'`);
  });

  it('a divisão de escopo espelha a do servidor: clique só na conversa', () => {
    // `CONTACT_BASE_KEYS = (UTM_KEYS + DERIVED_KEYS)` — sem os ids de clique.
    expect(ruby).toContain('CONTACT_BASE_KEYS = (UTM_KEYS + DERIVED_KEYS)');
    expect(ruby).toContain(
      'CONVERSATION_BASE_KEYS = (UTM_KEYS + CLICK_ID_KEYS + DERIVED_KEYS)'
    );

    expect(contactOriginKeys()).not.toContain('first_gclid');
    expect(conversationOriginKeys()).toContain('last_gclid');
  });

  it('as chaves saem prefixadas, como o banco as guarda', () => {
    expect(contactOriginKeys()).toContain('first_utm_source');
    expect(contactOriginKeys()).toContain('first_origin_kind');
    expect(conversationOriginKeys()).toContain('last_page_path');
  });

  it('`nao_disponivel` está no vocabulário — ausência tem nome (1.19)', () => {
    expect(ORIGIN_KINDS).toContain('nao_disponivel');
    expect(ORIGIN_KINDS).not.toContain('direta');
  });
});

/**
 * `hasSiteContext` é a ÚNICA regra que decide se a seção "recebido do site" aparece — o
 * `SiteContext.vue` a usa para esconder o conteúdo e o `ContactPanel.vue` para esconder o
 * `AccordionItem` ao redor. Enquanto essa regra existiu só dentro do componente, o cabeçalho
 * aparecia vazio em toda conversa de WhatsApp, e-mail e API.
 *
 * Aqui ela é medida sozinha, caso a caso. O comportamento no painel montado está em
 * `routes/dashboard/conversation/specs/ContactPanel.siteContext.spec.js`.
 */
describe('5.23 — `hasSiteContext`, a regra única do "tem o que dizer?"', () => {
  it('sem argumento nenhum, é falso — o caso do WhatsApp/e-mail/API', () => {
    expect(hasSiteContext()).toBe(false);
    expect(hasSiteContext({})).toBe(false);
  });

  it('um atributo de origem do CONTATO já basta', () => {
    expect(
      hasSiteContext({ contactAttributes: { first_utm_campaign: 'bf' } })
    ).toBe(true);
  });

  it('um atributo de origem da CONVERSA já basta', () => {
    expect(
      hasSiteContext({ conversationAttributes: { last_gclid: 'CjwK' } })
    ).toBe(true);
  });

  it('a identidade sozinha já basta (4.15)', () => {
    expect(hasSiteContext({ identifier: 'CRM-4711' })).toBe(true);
  });

  /**
   * A distinção inteira do bloco: o que o AGENTE digitou não faz a seção do SITE aparecer. Uma
   * guarda preguiçosa (`Object.keys(atributos).length`) daria verdadeiro aqui e traria o
   * acordeão vazio de volta para todo contato que tenha qualquer atributo personalizado.
   */
  it('atributo do agente NÃO conta, nem com o prefixo certo', () => {
    expect(
      hasSiteContext({
        contactAttributes: { plano_do_cliente: 'ouro', first_contato: 'ana' },
        conversationAttributes: { last_contato: 'joao' },
      })
    ).toBe(false);
  });

  it('valor vazio, nulo ou indefinido não conta — a regra do 1.19', () => {
    expect(
      hasSiteContext({
        contactAttributes: {
          first_utm_campaign: '',
          first_utm_source: null,
          first_utm_medium: undefined,
        },
        conversationAttributes: { last_page_path: '' },
        identifier: '',
      })
    ).toBe(false);
  });

  /**
   * `0` e `false` são VALORES e precisam contar. `!valor` os descartaria — e um `utm_content=0`
   * vindo de uma campanha real faria a seção sumir sem ninguém entender por quê.
   */
  it('`0` e `false` contam, porque são valores', () => {
    expect(
      hasSiteContext({ contactAttributes: { first_utm_content: 0 } })
    ).toBe(true);
    expect(
      hasSiteContext({ conversationAttributes: { last_utm_term: false } })
    ).toBe(true);
  });
});
