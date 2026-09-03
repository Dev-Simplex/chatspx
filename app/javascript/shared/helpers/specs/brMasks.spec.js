import {
  UF_LIST,
  applyMask,
  isValidCPF,
  isValidCNPJ,
  isValidCpfOrCnpj,
  isValidCEP,
  isValidUF,
  isCorporateEmail,
  isPhoneWithDialCode,
  looksLikeJunkName,
  looksLikeJunkPhone,
  looksLikeJunkEmail,
  validateFieldValue,
} from 'shared/helpers/brMasks';

// Mecanismo do aceite do bloco 3.13 (Onda 2) e dos itens 22-25 da §C.3 do plano 23.
describe('brMasks — máscaras', () => {
  it('formata CPF enquanto se digita, sem passar de 11 dígitos', () => {
    expect(applyMask('529', 'cpf')).toBe('529');
    expect(applyMask('529982', 'cpf')).toBe('529.982');
    expect(applyMask('52998224725', 'cpf')).toBe('529.982.247-25');
    expect(applyMask('529982247259999', 'cpf')).toBe('529.982.247-25');
  });

  it('formata CNPJ', () => {
    expect(applyMask('11222333000181', 'cnpj')).toBe('11.222.333/0001-81');
  });

  it('alterna CPF e CNPJ pelo comprimento', () => {
    expect(applyMask('52998224725', 'cpf_cnpj')).toBe('529.982.247-25');
    expect(applyMask('11222333000181', 'cpf_cnpj')).toBe('11.222.333/0001-81');
  });

  it('formata CEP', () => {
    expect(applyMask('01310930', 'cep')).toBe('01310-930');
  });

  it('formata telefone brasileiro com e sem nono dígito', () => {
    expect(applyMask('1132224444', 'phone')).toBe('(11) 3222-4444');
    expect(applyMask('11987654321', 'phone')).toBe('(11) 98765-4321');
  });

  it('deixa telefone com DDI intacto, porque quem tem + não é número nacional', () => {
    expect(applyMask('+5511987654321', 'phone')).toBe('+5511987654321');
  });

  it('põe UF em maiúscula e corta em duas letras', () => {
    expect(applyMask('sp', 'uf')).toBe('SP');
    expect(applyMask('spx', 'uf')).toBe('SP');
  });

  it('devolve o valor intacto quando a máscara não existe', () => {
    expect(applyMask('qualquer coisa', 'banana')).toBe('qualquer coisa');
    expect(applyMask('qualquer coisa', null)).toBe('qualquer coisa');
  });
});

describe('brMasks — CPF', () => {
  it('aceita 529.982.247-25', () => {
    expect(isValidCPF('529.982.247-25')).toBe(true);
    expect(isValidCPF('52998224725')).toBe(true);
  });

  it('rejeita 529.982.247-26 pelo dígito verificador', () => {
    expect(isValidCPF('529.982.247-26')).toBe(false);
  });

  // A armadilha da §B.4.3: o DV sozinho ACEITA 111.111.111-11.
  it('rejeita 111.111.111-11 pela regra de dígitos repetidos', () => {
    expect(isValidCPF('111.111.111-11')).toBe(false);
  });

  it('rejeita as outras nove sequências de dígito único', () => {
    const repeated = '0123456789'
      .split('')
      .map(digit => digit.repeat(11))
      .filter(cpf => isValidCPF(cpf));
    expect(repeated).toEqual([]);
  });

  it('rejeita comprimento diferente de 11', () => {
    expect(isValidCPF('5299822472')).toBe(false);
    expect(isValidCPF('529982247255')).toBe(false);
    expect(isValidCPF('')).toBe(false);
  });
});

describe('brMasks — CNPJ', () => {
  it('aceita 11.222.333/0001-81', () => {
    expect(isValidCNPJ('11.222.333/0001-81')).toBe(true);
  });

  it('rejeita 11.222.333/0001-82 pelo dígito verificador', () => {
    expect(isValidCNPJ('11.222.333/0001-82')).toBe(false);
  });

  it('rejeita 11.111.111/1111-11 pela mesma regra de dígitos repetidos', () => {
    expect(isValidCNPJ('11.111.111/1111-11')).toBe(false);
  });
});

describe('brMasks — CPF ou CNPJ, CEP e UF', () => {
  it('aceita os dois documentos e recusa o que não fecha', () => {
    expect(isValidCpfOrCnpj('529.982.247-25')).toBe(true);
    expect(isValidCpfOrCnpj('11.222.333/0001-81')).toBe(true);
    expect(isValidCpfOrCnpj('111.111.111-11')).toBe(false);
    expect(isValidCpfOrCnpj('5299822472')).toBe(false);
  });

  it('aceita CEP de 8 dígitos e recusa 00000-000', () => {
    expect(isValidCEP('01310-930')).toBe(true);
    expect(isValidCEP('0131093')).toBe(false);
    expect(isValidCEP('00000-000')).toBe(false);
  });

  it('conhece as 27 unidades da federação', () => {
    expect(UF_LIST).toHaveLength(27);
    expect(isValidUF('sp')).toBe(true);
    expect(isValidUF('DF')).toBe(true);
    expect(isValidUF('XX')).toBe(false);
  });
});

describe('brMasks — e-mail corporativo', () => {
  it('rejeita provedor gratuito e aceita domínio próprio', () => {
    expect(isCorporateEmail('fulano@gmail.com')).toBe(false);
    expect(isCorporateEmail('fulano@empresa.com.br')).toBe(true);
  });

  it('rejeita os gratuitos brasileiros mais comuns', () => {
    [
      'bol.com.br',
      'uol.com.br',
      'terra.com.br',
      'ig.com.br',
      'hotmail.com',
      'outlook.com',
      'yahoo.com.br',
    ].forEach(domain =>
      expect(isCorporateEmail(`fulano@${domain}`)).toBe(false)
    );
  });

  it('rejeita e-mail que nem é e-mail', () => {
    expect(isCorporateEmail('fulano')).toBe(false);
    expect(isCorporateEmail('')).toBe(false);
  });
});

describe('brMasks — telefone', () => {
  it('exige DDI', () => {
    expect(isPhoneWithDialCode('+5511987654321')).toBe(true);
    expect(isPhoneWithDialCode('11987654321')).toBe(false);
  });

  it('recusa número curto demais para ser telefone', () => {
    expect(isPhoneWithDialCode('+551')).toBe(false);
  });
});

describe('brMasks — as três regras anti-lixo', () => {
  it('regra 1: nome com menos de 2 caracteres, sem vogal, ou com 3 iguais seguidos', () => {
    expect(looksLikeJunkName('a')).toBe(true);
    expect(looksLikeJunkName('xzcv')).toBe(true);
    expect(looksLikeJunkName('aaaa')).toBe(true);
    expect(looksLikeJunkName('João Silva')).toBe(false);
    expect(looksLikeJunkName('Ana')).toBe(false);
  });

  it('regra 2: telefone com dígitos todos iguais ou sequência trivial', () => {
    expect(looksLikeJunkPhone('+55 11 11111-1111')).toBe(true);
    expect(looksLikeJunkPhone('123456789')).toBe(true);
    // Numero de teste escolhido a dedo: `+5511987654321`, que o resto desta
    // suite usa, TERMINA em 987654321 — ele proprio uma sequencia decrescente.
    // Usa-lo aqui como "telefone bom" seria escrever a regra ao contrario.
    expect(looksLikeJunkPhone('+5511993827465')).toBe(false);
  });

  it('regra 3: e-mail de domínio descartável', () => {
    expect(looksLikeJunkEmail('fulano@mailinator.com')).toBe(true);
    expect(looksLikeJunkEmail('fulano@yopmail.com')).toBe(true);
    expect(looksLikeJunkEmail('fulano@empresa.com.br')).toBe(false);
    expect(looksLikeJunkEmail('fulano@gmail.com')).toBe(false);
  });
});

describe('brMasks — validateFieldValue', () => {
  it('devolve severidade error para documento inválido, com o código do erro', () => {
    expect(validateFieldValue('111.111.111-11', { validator: 'cpf' })).toEqual({
      valid: false,
      severity: 'error',
      code: 'CPF',
    });
  });

  it('devolve severidade WARNING para anti-lixo — o bloqueio é suave', () => {
    expect(validateFieldValue('aaaa', { validator: 'junk_name' })).toEqual({
      valid: false,
      severity: 'warning',
      code: 'JUNK_NAME',
    });
  });

  it('campo vazio e não obrigatório passa, mesmo com validador ligado', () => {
    expect(validateFieldValue('', { validator: 'cpf' })).toEqual({
      valid: true,
      severity: null,
      code: null,
    });
  });

  it('campo vazio e obrigatório falha com o código REQUIRED', () => {
    expect(
      validateFieldValue('', { validator: 'cpf', required: true })
    ).toEqual({
      valid: false,
      severity: 'error',
      code: 'REQUIRED',
    });
  });

  it('validador desconhecido não inventa erro', () => {
    expect(validateFieldValue('qualquer', { validator: 'banana' })).toEqual({
      valid: true,
      severity: null,
      code: null,
    });
  });
});
