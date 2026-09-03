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
