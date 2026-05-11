/**
 * PII sanitizer used before forwarding agent draft / context to Captain.
 *
 * Defense-in-depth pair with `lib/captain/pii_sanitizer.rb` on the backend:
 * the frontend masks aggressively to keep PII out of server logs, the backend
 * masks again before injecting into LLM prompts.
 *
 * Patterns are conservative — false-positive cost > false-negative cost in this
 * domain. Card numbers run through the Luhn check to avoid masking long
 * non-card digit strings (barcodes, IDs).
 *
 * Usage:
 *   const { clean, redactions } = sanitizePII(text);
 *   useTrack('ai.pii.redacted', { count: redactions.length });
 */

// Order matters: more specific patterns first (CNPJ before CPF, phone before
// CPF/CEP) so that broader matches don't "steal" the digits. Email and CEP
// are off by default — agents legitimately exchange them with customers.
const PII_PATTERNS = [
  {
    name: 'cnpj',
    regex: /\b\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2}\b/g,
    mask: '[CNPJ]',
  },
  // BR phone — handles +55 prefix, optional parentheses, optional 9 prefix.
  // No \b on the left because `+` isn't a word char (would never match).
  {
    name: 'phone_br',
    regex: /(?:\+?55\s?)?\(?\b\d{2}\)?\s?9?\d{4}-?\d{4}\b/g,
    mask: '[TELEFONE]',
  },
  { name: 'cpf', regex: /\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/g, mask: '[CPF]' },
  // Card has 13–19 digits, possibly separated by spaces or dashes.
  // Luhn check applied below to reduce false positives.
  { name: 'card', regex: /\b(?:\d[ -]*?){13,19}\b/g, mask: '[CARTAO]' },
  {
    name: 'email',
    regex: /\b[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}\b/g,
    mask: '[EMAIL]',
  },
  { name: 'cep', regex: /\b\d{5}-?\d{3}\b/g, mask: '[CEP]' },
];

const ALL_TYPES = ['cnpj', 'phone_br', 'cpf', 'card'];

/**
 * Validates a numeric string against the Luhn / Mod-10 algorithm. Used to
 * reject false-positive card matches (e.g. barcodes, account numbers).
 * @param {string} num — bare digits, no spaces/dashes
 * @returns {boolean}
 */
export function isValidLuhn(num) {
  if (typeof num !== 'string' || !/^\d{13,19}$/.test(num)) return false;
  let sum = 0;
  let shouldDouble = false;
  for (let i = num.length - 1; i >= 0; i -= 1) {
    let n = parseInt(num.charAt(i), 10);
    if (shouldDouble) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    shouldDouble = !shouldDouble;
  }
  return sum % 10 === 0;
}

/**
 * Redacts PII patterns inside `text`. Default `enabledTypes` covers CPF, CNPJ,
 * phone numbers and credit cards — email/CEP are off by default since agents
 * legitimately exchange them with customers.
 *
 * @param {string} text
 * @param {Object} [options]
 * @param {string[]} [options.enabledTypes] — pattern names to enable
 * @returns {{ clean: string, redactions: Array<{ name: string, original: string }> }}
 */
export function sanitizePII(text, { enabledTypes = ALL_TYPES } = {}) {
  if (!text || typeof text !== 'string') {
    return { clean: text, redactions: [] };
  }
  let clean = text;
  const redactions = [];
  PII_PATTERNS.filter(p => enabledTypes.includes(p.name)).forEach(
    ({ name, regex, mask }) => {
      clean = clean.replace(regex, match => {
        if (name === 'card') {
          const digits = match.replace(/[ -]/g, '');
          if (!isValidLuhn(digits)) return match;
        }
        if (name === 'cpf') {
          const digits = match.replace(/\D/g, '');
          // Reject all-same-digit CPFs (00000000000, 11111111111, ...)
          if (/^(\d)\1+$/.test(digits)) return match;
        }
        redactions.push({ name, original: match });
        return mask;
      });
    }
  );
  return { clean, redactions };
}

export const PII_TYPES = Object.freeze({
  ALL: ALL_TYPES,
  EMAIL: 'email',
  CEP: 'cep',
});
