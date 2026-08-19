import fs from 'fs';
import path from 'path';
import {
  NAME_MAX_LENGTH,
  NAME_PREFIX,
  PII_KEYS,
  nameViolation,
  piiViolation,
} from '../trackContract';

/**
 * Bloco 5.16 — as três regras de nome e a recusa de PII, do lado do site.
 *
 * O último `it` é o que impede este arquivo de virar uma quarta fonte da verdade: ele lê o
 * MODELO Ruby e exige que as regras batam. Duas cópias que ninguém compara divergem; duas cópias
 * comparadas por um teste são uma cópia com redundância.
 */
const modeloRuby = fs.readFileSync(
  path.resolve(process.cwd(), 'app/models/tracking_event.rb'),
  'utf8'
);

describe('5.16 — o contrato de `track()`', () => {
  describe('nome', () => {
    it('aceita o evento próprio do cliente, no vocabulário do contrato', () => {
      expect(nameViolation('chatspx_orcamento_pedido')).toBeNull();
    });

    it('recusa nome sem o prefixo — e a recusa NOMEIA a regra', () => {
      // Prefixar sozinho seria pior que recusar: `track('lead')` viraria `chatspx_lead`, que é o
      // evento #5 do contrato, e o evento do cliente se misturaria ao nosso na conta dele.
      expect(nameViolation('orcamento_pedido')).toContain(NAME_PREFIX);
      expect(nameViolation('lead')).toContain(NAME_PREFIX);
    });

    it('recusa o que não é snake_case', () => {
      expect(nameViolation('chatspx_OrcamentoPedido')).toContain('snake_case');
      expect(nameViolation('chatspx_orcamento-pedido')).toContain('snake_case');
      expect(nameViolation('chatspx_orçamento')).toContain('snake_case');
    });

    it('recusa acima de 40 caracteres, que é limite do GA4', () => {
      const nome = `${NAME_PREFIX}${'a'.repeat(NAME_MAX_LENGTH)}`;
      expect(nome.length).toBeGreaterThan(NAME_MAX_LENGTH);
      expect(nameViolation(nome)).toContain(String(NAME_MAX_LENGTH));
      expect(
        nameViolation(
          `${NAME_PREFIX}${'a'.repeat(NAME_MAX_LENGTH - NAME_PREFIX.length)}`
        )
      ).toBeNull();
    });

    it('recusa o que não é string', () => {
      [null, undefined, 42, {}, ''].forEach(valor =>
        expect(nameViolation(valor)).toBeTruthy()
      );
    });
  });

  describe('PII', () => {
    it('encontra a chave, com qualquer caixa', () => {
      expect(piiViolation({ email: 'a@b.c' })).toBe('email');
      expect(piiViolation({ Phone_Number: '+55' })).toBe('Phone_Number');
      expect(piiViolation({ em: 'hash' })).toBe('em');
    });

    it('deixa passar o que não é PII', () => {
      expect(piiViolation({ value: 10, currency: 'BRL' })).toBeNull();
      expect(piiViolation()).toBeNull();
    });
  });

  it('as regras são as MESMAS do modelo que grava (`TrackingEvent`)', () => {
    expect(modeloRuby).toContain(`NAME_PREFIX = '${NAME_PREFIX}'`);
    expect(modeloRuby).toContain(`NAME_MAX_LENGTH = ${NAME_MAX_LENGTH}`);

    const piiDoModelo = /PII_KEYS = %w\[([^\]]+)\]/
      .exec(modeloRuby)[1]
      .trim()
      .split(/\s+/);
    expect([...PII_KEYS].sort()).toEqual([...piiDoModelo].sort());
  });
});
