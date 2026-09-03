/**
 * Bloco 3.13 da Onda 2 — máscaras e validadores brasileiros do pré-chat.
 *
 * FONTE ÚNICA, não espelho. O plano pedia `dashboard/helper/brMasks.js` "+
 * espelho no widget"; duas cópias divergem no primeiro conserto feito de um
 * lado só, e aí a tela promete uma regra e o widget aplica outra. Este arquivo
 * mora em `shared/`, que os dois grafos já importam
 * (`shared/helpers/Validators.js` é usado pelo widget e pelo dashboard), e os
 * dois `helper/brMasks.js` são reexportações de uma linha.
 *
 * Os nomes de `mask` e `validator` aqui são os MESMOS de
 * `Channel::WebWidget::PreChatFormSchema` (bloco 3.12). Nome que exista de um
 * lado só é campo que a tela oferece e o widget ignora.
 *
 * PESO: nenhuma dependência nova. Duas foram consideradas e recusadas, com o
 * número medido:
 *  - `company-email-validator` (`package.json:80`) carrega
 *    `free_email_provider_domains.js` com **222.995 bytes** de domínios. O
 *    widget tem teto de 300 kB no grafo inteiro (gate do bloco 0.5) — uma lista
 *    de domínios levaria dois terços dele. Aqui vai uma lista curta, explícita
 *    e auditável.
 *  - `libphonenumber-js` **não está no grafo do widget hoje** (medido: só o
 *    dashboard o importa; o widget usa `startsWithPlus` +
 *    `isPhoneNumberValidWithDialCode` de `shared/helpers/Validators.js`,
 *    registrados no FormKit em `entrypoints/widget.js:36-38`). Seu
 *    `metadata.full.json` tem 156 kB. Reusamos as duas regras que já existem —
 *    que é, literalmente, o que o item 25 da §C.3 do plano 23 pede.
 */
import {
  startsWithPlus,
  isPhoneNumberValidWithDialCode,
} from 'shared/helpers/Validators';

export const UF_LIST = [
  { code: 'AC', name: 'Acre' },
  { code: 'AL', name: 'Alagoas' },
  { code: 'AP', name: 'Amapá' },
  { code: 'AM', name: 'Amazonas' },
  { code: 'BA', name: 'Bahia' },
  { code: 'CE', name: 'Ceará' },
  { code: 'DF', name: 'Distrito Federal' },
  { code: 'ES', name: 'Espírito Santo' },
  { code: 'GO', name: 'Goiás' },
  { code: 'MA', name: 'Maranhão' },
  { code: 'MT', name: 'Mato Grosso' },
  { code: 'MS', name: 'Mato Grosso do Sul' },
  { code: 'MG', name: 'Minas Gerais' },
  { code: 'PA', name: 'Pará' },
  { code: 'PB', name: 'Paraíba' },
  { code: 'PR', name: 'Paraná' },
  { code: 'PE', name: 'Pernambuco' },
  { code: 'PI', name: 'Piauí' },
  { code: 'RJ', name: 'Rio de Janeiro' },
  { code: 'RN', name: 'Rio Grande do Norte' },
  { code: 'RS', name: 'Rio Grande do Sul' },
  { code: 'RO', name: 'Rondônia' },
  { code: 'RR', name: 'Roraima' },
  { code: 'SC', name: 'Santa Catarina' },
  { code: 'SP', name: 'São Paulo' },
  { code: 'SE', name: 'Sergipe' },
  { code: 'TO', name: 'Tocantins' },
];

const UF_CODES = new Set(UF_LIST.map(uf => uf.code));

/** Provedores gratuitos — quem os usa não está dando o e-mail da empresa. */
const FREE_EMAIL_DOMAINS = new Set([
  'gmail.com',
  'googlemail.com',
  'hotmail.com',
  'hotmail.com.br',
  'outlook.com',
  'outlook.com.br',
  'live.com',
  'live.com.br',
  'msn.com',
  'yahoo.com',
  'yahoo.com.br',
  'ymail.com',
  'icloud.com',
  'me.com',
  'mac.com',
  'aol.com',
  'gmx.com',
  'gmx.net',
  'protonmail.com',
  'proton.me',
  'zoho.com',
  'yandex.com',
  'yandex.ru',
  'mail.ru',
  'mail.com',
  'uol.com.br',
  'bol.com.br',
  'terra.com.br',
  'ig.com.br',
  'r7.com',
  'globo.com',
  'globomail.com',
  'oi.com.br',
  'zipmail.com.br',
  'superig.com.br',
  'click21.com.br',
  'pop.com.br',
  'brturbo.com.br',
  'itelefonica.com.br',
  'yahoo.com.ar',
  'hotmail.es',
  'gmail.com.br',
]);

/** Descartáveis — endereço que existe por dez minutos. Regra 3 do anti-lixo. */
const DISPOSABLE_EMAIL_DOMAINS = new Set([
  'mailinator.com',
  'yopmail.com',
  'guerrillamail.com',
  'guerrillamail.info',
  'sharklasers.com',
  'grr.la',
  '10minutemail.com',
  '10minutemail.net',
  'tempmail.com',
  'temp-mail.org',
  'tempr.email',
  'throwawaymail.com',
  'trashmail.com',
  'trashmail.de',
  'dispostable.com',
  'getnada.com',
  'nada.email',
  'maildrop.cc',
  'mohmal.com',
  'fakeinbox.com',
  'mytemp.email',
  'emailondeck.com',
  'spamgourmet.com',
  'mailnesia.com',
  'inboxkitten.com',
  'harakirimail.com',
  'moakt.com',
  'tmpmail.org',
  'discard.email',
  'byom.de',
]);

const MASK_PATTERNS = {
  cpf: { digits: 11, pattern: '###.###.###-##' },
  cnpj: { digits: 14, pattern: '##.###.###/####-##' },
  cep: { digits: 8, pattern: '#####-###' },
};

export const MASK_NAMES = ['cpf', 'cnpj', 'cpf_cnpj', 'cep', 'uf', 'phone'];

export const VALIDATOR_NAMES = [
  'cpf',
  'cnpj',
  'cpf_cnpj',
  'cep',
  'uf',
  'email',
  'corporate_email',
  'phone',
  'junk_name',
  'junk_phone',
  'junk_email',
];

/**
 * @param {string} value
 * @returns {string} Só os dígitos do valor.
 */
export const onlyDigits = (value = '') =>
  String(value ?? '').replace(/\D/g, '');

const formatByPattern = (digits, pattern) => {
  let index = 0;
  return pattern.split('').reduce((out, char) => {
    // Sem dígito para consumir, o separador seguinte também não entra: é o que
    // faz `529982` sair como `529.982` e não como `529.982.`.
    if (index >= digits.length) return out;
    if (char !== '#') return out + char;
    index += 1;
    return out + digits[index - 1];
  }, '');
};

const maskPhone = value => {
  // Quem digitou `+` está informando DDI: o formato nacional não se aplica e
  // reescrever o valor atrapalharia quem cola um número internacional.
  if (
    String(value ?? '')
      .trim()
      .startsWith('+')
  )
    return value;

  const digits = onlyDigits(value).slice(0, 11);
  if (digits.length <= 2) return digits;
  if (digits.length <= 6) return `(${digits.slice(0, 2)}) ${digits.slice(2)}`;
  if (digits.length <= 10) {
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`;
  }
  return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`;
};

/**
 * Aplica a máscara enquanto se digita. Valor com máscara desconhecida sai
 * intacto — máscara que não existe não pode comer o que o visitante escreveu.
 *
 * @param {string} value
 * @param {string} mask - um de MASK_NAMES.
 * @returns {string}
 */
export const applyMask = (value, mask) => {
  if (mask === 'uf') {
    return String(value ?? '')
      .replace(/[^a-zA-Z]/g, '')
      .toUpperCase()
      .slice(0, 2);
  }
  if (mask === 'phone') return maskPhone(value);

  let resolved = mask;
  if (mask === 'cpf_cnpj') {
    resolved = onlyDigits(value).length > 11 ? 'cnpj' : 'cpf';
  }
  const spec = MASK_PATTERNS[resolved];
  if (!spec) return value;

  return formatByPattern(onlyDigits(value).slice(0, spec.digits), spec.pattern);
};

const hasRepeatedDigitsOnly = digits =>
  digits.length > 0 && new Set(digits).size === 1;

const checkDigit = (digits, weights) => {
  const sum = weights.reduce(
    (acc, weight, index) => acc + Number(digits[index]) * weight,
    0
  );
  const remainder = sum % 11;
  return remainder < 2 ? 0 : 11 - remainder;
};

/**
 * CPF: comprimento, dígitos repetidos e os dois dígitos verificadores.
 *
 * A REGRA DE DÍGITOS REPETIDOS NÃO É ENFEITE (§B.4.3 do plano 23): o algoritmo
 * oficial do DV **aceita** `111.111.111-11` — a soma ponderada de `111111111`
 * dá 54, `11 − 54 % 11 = 1`, e o mesmo acontece com o segundo dígito. Uma
 * implementação que faça só o DV valida o CPF de teste mais óbvio que existe.
 * O mesmo vale para as outras nove sequências de dígito único.
 *
 * @param {string} value
 * @returns {boolean}
 */
export const isValidCPF = value => {
  const digits = onlyDigits(value);
  if (digits.length !== 11) return false;
  if (hasRepeatedDigitsOnly(digits)) return false;

  const first = checkDigit(digits, [10, 9, 8, 7, 6, 5, 4, 3, 2]);
  const second = checkDigit(digits, [11, 10, 9, 8, 7, 6, 5, 4, 3, 2]);
  return first === Number(digits[9]) && second === Number(digits[10]);
};

/**
 * CNPJ: mesma estrutura do CPF, mesma armadilha — `11.111.111/1111-11` passa
 * pelo DV sozinho.
 *
 * @param {string} value
 * @returns {boolean}
 */
export const isValidCNPJ = value => {
  const digits = onlyDigits(value);
  if (digits.length !== 14) return false;
  if (hasRepeatedDigitsOnly(digits)) return false;

  const first = checkDigit(digits, [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  const second = checkDigit(digits, [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  return first === Number(digits[12]) && second === Number(digits[13]);
};

/**
 * @param {string} value
 * @returns {boolean} Verdadeiro para CPF válido OU CNPJ válido.
 */
export const isValidCpfOrCnpj = value => {
  const digits = onlyDigits(value);
  if (digits.length === 11) return isValidCPF(value);
  if (digits.length === 14) return isValidCNPJ(value);
  return false;
};

/**
 * @param {string} value
 * @returns {boolean} Oito dígitos que não sejam todos iguais.
 */
export const isValidCEP = value => {
  const digits = onlyDigits(value);
  return digits.length === 8 && !hasRepeatedDigitsOnly(digits);
};

/**
 * @param {string} value
 * @returns {boolean} Verdadeiro para uma das 27 unidades da federação.
 */
export const isValidUF = value =>
  UF_CODES.has(
    String(value ?? '')
      .trim()
      .toUpperCase()
  );

// Deliberadamente simples: e-mail é validado de verdade pelo servidor e pelo
// envio. Regex ambiciosa de e-mail rejeita endereço legítimo, que num
// formulário de captura é lead perdido.
const EMAIL_RE = /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/;

/**
 * @param {string} value
 * @returns {boolean}
 */
export const isValidEmail = value => EMAIL_RE.test(String(value ?? '').trim());

const emailDomain = value =>
  String(value ?? '')
    .trim()
    .toLowerCase()
    .split('@')[1] || '';

/**
 * @param {string} value
 * @returns {boolean} E-mail válido cujo domínio não é de provedor gratuito nem
 * descartável.
 */
export const isCorporateEmail = value => {
  if (!isValidEmail(value)) return false;
  const domain = emailDomain(value);
  return (
    !FREE_EMAIL_DOMAINS.has(domain) && !DISPOSABLE_EMAIL_DOMAINS.has(domain)
  );
};

/**
 * @param {string} value
 * @returns {boolean} Número com DDI (`+`) e comprimento plausível.
 */
export const isPhoneWithDialCode = value => {
  const raw = String(value ?? '').trim();
  if (!startsWithPlus(raw)) return false;
  return isPhoneNumberValidWithDialCode(raw.replace(/[\s()-]/g, ''));
};

const VOWELS_RE = /[aeiouáàâãéêíóôõúü]/i;

/**
 * Regra 1 do anti-lixo (§B.4.3): menos de 2 caracteres, sem vogal alguma, ou
 * três caracteres idênticos seguidos.
 *
 * @param {string} value
 * @returns {boolean} Verdadeiro quando o nome PARECE lixo — e "parece" é o
 * limite: quem decide é o visitante, porque o bloqueio é suave.
 */
export const looksLikeJunkName = value => {
  const name = String(value ?? '').trim();
  if (name.length < 2) return true;
  if (!VOWELS_RE.test(name)) return true;
  return /(.)\1\1/.test(name.toLowerCase());
};

const isStrictSequence = digits => {
  if (digits.length < 4) return false;
  const step = Number(digits[1]) - Number(digits[0]);
  if (step !== 1 && step !== -1) return false;
  return digits
    .split('')
    .every(
      (digit, index) =>
        index === 0 || Number(digit) - Number(digits[index - 1]) === step
    );
};

/**
 * Regra 2 do anti-lixo: todos os dígitos iguais, os últimos oito iguais (o
 * caso `+55 11 11111-1111`, em que DDI e DDD escondem a repetição), ou uma
 * sequência trivial de ponta a ponta.
 *
 * O recorte é o número inteiro, e não qualquer trecho dele, de propósito:
 * `+55 11 98765-4321` **termina** numa sequência decrescente e é um celular
 * plausível. Marcar por substring transformaria a regra num gerador de falso
 * positivo em cima de cliente real.
 *
 * @param {string} value
 * @returns {boolean}
 */
export const looksLikeJunkPhone = value => {
  const digits = onlyDigits(value);
  if (digits.length < 4) return true;
  if (hasRepeatedDigitsOnly(digits)) return true;
  if (digits.length >= 8 && hasRepeatedDigitsOnly(digits.slice(-8)))
    return true;
  return isStrictSequence(digits);
};

/**
 * Regra 3 do anti-lixo: domínio descartável. Provedor gratuito **não** entra
 * aqui — `gmail.com` é o e-mail real da maioria das pessoas físicas; quem quer
 * recusá-lo usa o validador `corporate_email`, que é uma escolha do cliente.
 *
 * @param {string} value
 * @returns {boolean}
 */
export const looksLikeJunkEmail = value =>
  DISPOSABLE_EMAIL_DOMAINS.has(emailDomain(value));

const VALIDATORS = {
  cpf: { test: isValidCPF, severity: 'error', code: 'CPF' },
  cnpj: { test: isValidCNPJ, severity: 'error', code: 'CNPJ' },
  cpf_cnpj: { test: isValidCpfOrCnpj, severity: 'error', code: 'CPF_CNPJ' },
  cep: { test: isValidCEP, severity: 'error', code: 'CEP' },
  uf: { test: isValidUF, severity: 'error', code: 'UF' },
  email: { test: isValidEmail, severity: 'error', code: 'EMAIL' },
  corporate_email: {
    test: isCorporateEmail,
    severity: 'error',
    code: 'CORPORATE_EMAIL',
  },
  phone: { test: isPhoneWithDialCode, severity: 'error', code: 'PHONE' },
  // As três anti-lixo são WARNING: o campo avisa e o visitante segue. Filtro
  // rígido em formulário de captura descarta cliente real (§B.4.3).
  junk_name: {
    test: value => !looksLikeJunkName(value),
    severity: 'warning',
    code: 'JUNK_NAME',
  },
  junk_phone: {
    test: value => !looksLikeJunkPhone(value),
    severity: 'warning',
    code: 'JUNK_PHONE',
  },
  junk_email: {
    test: value => !looksLikeJunkEmail(value),
    severity: 'warning',
    code: 'JUNK_EMAIL',
  },
};

const PASSED = { valid: true, severity: null, code: null };

/**
 * O veredito de um campo. `code` é sufixo de chave de i18n, nunca texto pronto:
 * a mensagem sai de `INBOX_WIDGET.PRE_CHAT_FORM.VALIDATION.<code>` ou do
 * `error_message` que o cliente escreveu no construtor.
 *
 * @param {string} value
 * @param {{validator?: string, required?: boolean}} options
 * @returns {{valid: boolean, severity: ?string, code: ?string}}
 */
export const validateFieldValue = (value, { validator, required } = {}) => {
  const raw = String(value ?? '').trim();

  if (!raw) {
    return required
      ? { valid: false, severity: 'error', code: 'REQUIRED' }
      : PASSED;
  }

  const rule = VALIDATORS[validator];
  if (!rule) return PASSED;

  return rule.test(raw)
    ? PASSED
    : { valid: false, severity: rule.severity, code: rule.code };
};
