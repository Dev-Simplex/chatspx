import { describe, it, expect } from 'vitest';
import { sanitizePII, isValidLuhn } from '../sanitizePII';

describe('sanitizePII — CPF', () => {
  it('redacts CPF with dots and dash', () => {
    const { clean, redactions } = sanitizePII('Meu CPF é 123.456.789-09 ok');
    expect(clean).toBe('Meu CPF é [CPF] ok');
    expect(redactions).toHaveLength(1);
    expect(redactions[0].name).toBe('cpf');
  });

  it('redacts CPF with no punctuation', () => {
    const { clean } = sanitizePII('CPF 12345678909');
    expect(clean).toBe('CPF [CPF]');
  });

  it('does not redact all-same-digit fake CPF (00000000000)', () => {
    const { clean, redactions } = sanitizePII('CPF 00000000000');
    expect(clean).toBe('CPF 00000000000');
    expect(redactions).toHaveLength(0);
  });
});

describe('sanitizePII — CNPJ', () => {
  it('redacts CNPJ with full punctuation', () => {
    const { clean } = sanitizePII('CNPJ 12.345.678/0001-90');
    expect(clean).toBe('CNPJ [CNPJ]');
  });

  it('redacts CNPJ with no punctuation', () => {
    const { clean } = sanitizePII('CNPJ 12345678000190');
    expect(clean).toBe('CNPJ [CNPJ]');
  });
});

describe('sanitizePII — phone (BR)', () => {
  it('redacts BR mobile with country code', () => {
    const { clean } = sanitizePII('Liga: +55 11 91234-5678');
    expect(clean).toBe('Liga: [TELEFONE]');
  });

  it('redacts BR mobile without country code', () => {
    const { clean } = sanitizePII('Liga (11) 91234-5678');
    expect(clean).toBe('Liga [TELEFONE]');
  });

  it('redacts compact BR mobile', () => {
    const { clean } = sanitizePII('11912345678');
    expect(clean).toBe('[TELEFONE]');
  });
});

describe('sanitizePII — credit card', () => {
  it('redacts a Luhn-valid Visa-style card', () => {
    // 4111 1111 1111 1111 — well known Luhn-valid Visa test number
    const { clean, redactions } = sanitizePII('Cartão 4111 1111 1111 1111');
    expect(clean).toBe('Cartão [CARTAO]');
    expect(redactions[0].name).toBe('card');
  });

  it('does NOT redact a Luhn-invalid 16-digit string', () => {
    const { clean } = sanitizePII('barcode 1234567890123456');
    expect(clean).toBe('barcode 1234567890123456');
  });

  it('does NOT redact a 20-digit barcode', () => {
    // 20 digits exceeds card length (>19), regex allows up to 19, so it should not match
    const { clean } = sanitizePII('barcode 12345678901234567890');
    expect(clean).toBe('barcode 12345678901234567890');
  });
});

describe('sanitizePII — email and CEP', () => {
  it('does NOT redact email by default', () => {
    const { clean, redactions } = sanitizePII('contato: foo@example.com');
    expect(clean).toBe('contato: foo@example.com');
    expect(redactions).toHaveLength(0);
  });

  it('redacts email when explicitly enabled', () => {
    const { clean } = sanitizePII('contato: foo@example.com', {
      enabledTypes: ['email'],
    });
    expect(clean).toBe('contato: [EMAIL]');
  });

  it('does NOT redact CEP by default', () => {
    const { clean } = sanitizePII('CEP 01310-100');
    expect(clean).toBe('CEP 01310-100');
  });

  it('redacts CEP when explicitly enabled', () => {
    const { clean } = sanitizePII('CEP 01310-100', { enabledTypes: ['cep'] });
    expect(clean).toBe('CEP [CEP]');
  });
});

describe('sanitizePII — edge cases', () => {
  it('returns empty inputs unchanged', () => {
    expect(sanitizePII('').clean).toBe('');
    expect(sanitizePII(null).clean).toBe(null);
    expect(sanitizePII(undefined).clean).toBe(undefined);
  });

  it('handles numbers/non-strings safely', () => {
    expect(sanitizePII(12345).clean).toBe(12345);
    expect(sanitizePII(12345).redactions).toEqual([]);
  });

  it('redacts multiple distinct types in a single string', () => {
    const text = 'CPF 123.456.789-09 e CNPJ 12.345.678/0001-90';
    const { clean, redactions } = sanitizePII(text);
    expect(clean).toBe('CPF [CPF] e CNPJ [CNPJ]');
    expect(redactions.map(r => r.name).sort()).toEqual(['cnpj', 'cpf']);
  });

  it('processes 10k chars in under 50ms', () => {
    const padded = 'x'.repeat(10000);
    const t0 = performance.now();
    sanitizePII(padded);
    const elapsed = performance.now() - t0;
    expect(elapsed).toBeLessThan(50);
  });
});

describe('isValidLuhn', () => {
  it('rejects non-strings', () => {
    expect(isValidLuhn(null)).toBe(false);
    expect(isValidLuhn(undefined)).toBe(false);
    expect(isValidLuhn(123)).toBe(false);
  });

  it('rejects strings that are not 13-19 digits', () => {
    expect(isValidLuhn('123')).toBe(false);
    expect(isValidLuhn('12345678901234567890')).toBe(false);
    expect(isValidLuhn('41111111111a1111')).toBe(false);
  });

  it('accepts the Visa test number 4111111111111111', () => {
    expect(isValidLuhn('4111111111111111')).toBe(true);
  });

  it('rejects a near-Luhn number that fails the check', () => {
    expect(isValidLuhn('4111111111111112')).toBe(false);
  });
});
