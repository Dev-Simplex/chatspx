import { mutations } from 'dashboard/store/modules/contacts/mutations';
import types from 'dashboard/store/mutation-types';
import { contactOriginKeys } from 'dashboard/helper/originAttributes';

/**
 * Bloco 5.23 — **a forma com que a store escreve, medida na store de verdade.**
 *
 * ── POR QUE ESTE ARQUIVO EXISTE ─────────────────────────────────────────────────────────
 *
 * No bloco 1.17 a linha "Endereço IP" nunca renderizou para ninguém, e o defeito não estava no
 * componente: a store cameliza o payload da API com `camelcaseKeys(..., { deep: true })`, então
 * o registro guarda `additionalAttributes.createdAtIp` enquanto o painel lia
 * `additional_attributes.created_at_ip`. Cada lado estava certo sozinho. Trinta testes de
 * unidade passaram; só o navegador mostrou.
 *
 * A defesa contra repetir isso não é "olhar com atenção" — é **passar o payload pela mutation
 * REAL** e verificar a forma que sai. Um mock de store não pega, porque o mock é escrito por
 * quem já acredita na forma errada.
 *
 * O que salva as chaves de origem é o `stopPaths: ['custom_attributes']` no `camelcaseKeys`. Se
 * alguém o remover, `first_utm_source` vira `firstUtmSource`, a seção do 5.23 fica vazia para
 * todo mundo — e nenhum teste de componente notaria, porque todos passam o objeto na mão.
 */
const payloadDaApi = {
  id: 7,
  name: 'Ana Souza',
  identifier: 'CRM-4711',
  additional_attributes: { created_at_ip: '203.0.113.77' },
  custom_attributes: {
    first_utm_source: 'google',
    first_utm_campaign: 'black-friday',
    first_origin_kind: 'busca_paga',
    plano_do_cliente: 'ouro',
  },
};

const guardaContato = () => {
  const state = { records: {}, sortOrder: [] };
  mutations[types.SET_CONTACT_ITEM](state, payloadDaApi);
  return state.records[7];
};

describe('5.23 — a forma que a store de contatos realmente escreve', () => {
  /**
   * O RESULTADO SURPREENDE, e é por isso que ele está fixado num teste em vez de num comentário:
   * o `stopPaths` protege o CONTEÚDO, não a chave do topo. Ela é camelizada como qualquer
   * outra, então o registro guarda `customAttributes` — com `first_utm_source` intacto dentro.
   *
   * Camelizado por fora, snake_case por dentro. Quem ler só o `stopPaths` conclui o contrário.
   */
  it('a chave do topo VIRA `customAttributes` — o `stopPaths` não a protege', () => {
    const contato = guardaContato();

    expect(contato.customAttributes).toBeDefined();
    expect(contato.custom_attributes).toBeUndefined();
  });

  it('mas o CONTEÚDO sobrevive em snake_case, chave por chave', () => {
    const contato = guardaContato();

    expect(contato.customAttributes.first_utm_source).toBe('google');
    expect(contato.customAttributes.first_origin_kind).toBe('busca_paga');
  });

  it('NENHUMA chave de origem é camelizada — é o que o `stopPaths` protege', () => {
    const contato = guardaContato();
    const chaves = Object.keys(contato.customAttributes || {});

    expect(chaves.some(c => /[A-Z]/.test(c))).toBe(false);
    expect(contato.customAttributes.firstUtmSource).toBeUndefined();
  });

  it('as chaves que o painel procura são exatamente as que a store guarda', () => {
    const contato = guardaContato();
    const guardadas = Object.keys(contato.customAttributes || {});
    const procuradas = contactOriginKeys();

    // as três de origem do payload estão entre as que o painel procura
    const deOrigem = guardadas.filter(c => procuradas.includes(c));
    expect(deOrigem.sort()).toEqual([
      'first_origin_kind',
      'first_utm_campaign',
      'first_utm_source',
    ]);
    // e o atributo do agente não está
    expect(procuradas).not.toContain('plano_do_cliente');
  });

  /**
   * A contraprova, e ela é o coração deste arquivo: `additional_attributes` É camelizado. Se um
   * dia o painel do 5.23 precisar de algo de lá, tem de ler a forma camelizada — como o 1.17
   * teve de aprender. Ter as duas asserções no mesmo lugar deixa a diferença impossível de ler
   * errado.
   */
  it('`additional_attributes`, ao contrário, VEM camelizado', () => {
    const contato = guardaContato();

    expect(contato.additionalAttributes?.createdAtIp).toBe('203.0.113.77');
    expect(contato.additional_attributes).toBeUndefined();
  });
});
