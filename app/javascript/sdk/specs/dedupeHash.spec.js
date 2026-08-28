import { describe, it, expect } from 'vitest';
import { dedupeHash } from '../dedupeHash';

/*
 * Bloco 2.18 — o hash que substituiu o pacote `md5` no `sdk.js`.
 *
 * O QUE ESTES TESTES PRECISAM ACUSAR. Um hash de dedupe errado NÃO quebra
 * nada visível: ele silenciosamente para de emitir `set-user` (colisão: dois
 * conjuntos de dados diferentes com o mesmo hash) ou passa a emitir toda vez
 * (instabilidade). Nos dois casos a suíte fica verde e o defeito só aparece
 * como "o contato não atualiza" meses depois. Por isso cada bloco abaixo
 * nomeia o hash ERRADO que ele reprova — teste que só chama a função e vê que
 * ela devolve string passaria com `() => 'x'`.
 */
describe('dedupeHash — o hash de dedupe do `setUser`', () => {
  describe('formato — 128 bits, sempre', () => {
    const amostra = [
      '',
      'a',
      'identifier',
      'emailana@exemplo.com.brnameAna',
      'chatspx — acentuação e emoji 🙂',
      'x'.repeat(10000),
    ];

    // REPROVA: estreitar para 32 bits (8 caracteres) e chamar de igual, que é
    // o jeito mais fácil de "simplificar" este arquivo e o que devolveria
    // colisão acidental em poucos milhares de visitantes.
    it.each(amostra)('%j vira 32 caracteres hex minúsculos', entrada => {
      expect(dedupeHash(entrada)).toMatch(/^[0-9a-f]{32}$/);
    });

    // REPROVA: `padStart` esquecido. Um lane que calha de valer 0x00ff0000
    // sairia com 6 dígitos e o hash inteiro encurtaria — mudando de tamanho
    // conforme o dado, o que nenhum teste de "é string" pegaria.
    it('não encurta quando um dos quatro blocos tem zeros à esquerda', () => {
      // 4.000 entradas: com 4 lanes de 32 bits, a chance de nenhuma delas
      // produzir um lane com byte alto zerado é desprezível.
      const tamanhos = new Set();
      for (let i = 0; i < 4000; i += 1) {
        tamanhos.add(dedupeHash(`visitante-${i}`).length);
      }
      expect([...tamanhos]).toEqual([32]);
    });
  });

  describe('sensibilidade — o que o hash tem de enxergar', () => {
    // REPROVA: hash pelo COMPRIMENTO da entrada. Foi exatamente o esboço usado
    // para medir quanto o `md5` pesava; se ele tivesse ficado no lugar, o
    // dedupe pararia de ver qualquer troca de e-mail do mesmo tamanho.
    it('distingue entradas de mesmo comprimento', () => {
      expect(dedupeHash('ana@exemplo.com.br')).not.toBe(
        dedupeHash('ivo@exemplo.com.br')
      );
    });

    // REPROVA: soma de `charCodeAt`, o hash caseiro de uma linha. Ele dá o
    // mesmo valor para qualquer anagrama — `nameAna` e `nameNaa` colidiriam.
    it('distingue permutações dos mesmos caracteres', () => {
      expect(dedupeHash('ab')).not.toBe(dedupeHash('ba'));
      expect(dedupeHash('nameAnacityRio')).not.toBe(
        dedupeHash('nameAnacityoRi')
      );
    });

    // REPROVA: hash que só olha um prefixo da entrada. `getUserString`
    // concatena os campos numa ordem fixa, e `custom_attributes` é o ÚLTIMO —
    // um hash que para nos primeiros N caracteres nunca veria mudança neles.
    it('enxerga mudança no fim de uma entrada longa', () => {
      const base = 'x'.repeat(4096);
      expect(dedupeHash(`${base}a`)).not.toBe(dedupeHash(`${base}b`));
    });

    it('é estável: a mesma entrada dá sempre o mesmo hash', () => {
      const entrada = 'emailana@exemplo.com.brphone_number+5511999998888';
      expect(dedupeHash(entrada)).toBe(dedupeHash(entrada));
    });
  });

  describe('largura efetiva — os 128 bits são 128 bits', () => {
    const N = 2000;
    const hashes = [];
    for (let i = 0; i < N; i += 1) {
      hashes.push(dedupeHash(`email=user-${i}@exemplo.com.br&id=${i}`));
    }
    const lane = (h, k) => h.slice(k * 8, k * 8 + 8);

    // REPROVA: 32 bits disfarçados de 128 — o mesmo lane repetido quatro
    // vezes, ou três lanes de preenchimento constante. Os dois passariam em
    // todos os testes acima e colidiriam como um hash de 32 bits.
    it.each([0, 1, 2, 3])('o bloco %i varia de forma independente', indice => {
      const distintos = new Set(hashes.map(h => lane(h, indice)));
      expect(distintos.size).toBeGreaterThanOrEqual(N * 0.999);
    });

    it('os quatro blocos de uma mesma entrada não são cópias', () => {
      const iguais = hashes.filter(h => {
        const l = [0, 1, 2, 3].map(k => lane(h, k));
        return new Set(l).size < 4;
      });
      expect(iguais).toEqual([]);
    });

    // REPROVA: qualquer estreitamento real. Com 128 bits, 200.000 entradas
    // colidem com probabilidade ~5e-29; com 32 bits, o esperado é ~4,6
    // colisões e este teste fica vermelho quase sempre.
    it('200.000 entradas distintas produzem 200.000 hashes distintos', () => {
      const vistos = new Set();
      for (let i = 0; i < 200000; i += 1) {
        vistos.add(dedupeHash(`user-${i}@exemplo.com.br`));
      }
      expect(vistos.size).toBe(200000);
    });
  });

  /*
   * O VALOR VIAJA NO COOKIE `cw_user_<websiteToken>`, no navegador do
   * visitante, e é comparado com o que for calculado na PRÓXIMA visita. Trocar
   * o algoritmo invalida todos os cookies em circulação: cada visitante já
   * identificado emite um `set-user` a mais. Foi uma decisão consciente ao
   * sair do `md5` (está escrita em `dedupeHash.js`); o que estes vetores
   * impedem é que aconteça de novo SEM decisão — uma constante trocada, um
   * `>>>` virando `>>`, um `imul` virando `*`.
   */
  describe('vetores congelados — o cookie em circulação é contrato', () => {
    it.each([
      ['', '027ae52ecfc796215593990d4b41437c'],
      ['a', '5eb8e4e408dee1678f5f05b958089485'],
      ['ab', '2cbb33e91d23e67b6983748780a2fccd'],
      ['ba', '1bd9bada35d52f26ee0ad23e2660a00e'],
      ['identifier', 'e74cf99999bc2707f73a7c49f8f59db9'],
      ['emailana@exemplo.com.brnameAna', '6dd292d6c9a2566f32ecba6cac1c4784'],
      ['chatspx — acentuação e emoji 🙂', 'df5becfe77ea046aca0c0f84ed4404aa'],
    ])('%j → %s', (entrada, esperado) => {
      expect(dedupeHash(entrada)).toBe(esperado);
    });
  });
});
