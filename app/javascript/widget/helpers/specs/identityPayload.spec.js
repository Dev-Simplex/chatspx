import { buildContactPayload, flattenCompany } from '../identityPayload';

// Bloco 5.17 — a traducao entre o vocabulario do SITE e o da API do contato.
describe('flattenCompany', () => {
  it('company como OBJETO vira company_name, que e o que a API entende', () => {
    expect(flattenCompany({ name: 'Simplex' })).toEqual({
      company_name: 'Simplex',
    });
  });

  it('os outros campos da empresa viram atributos com prefixo, sem colidir com os do cliente', () => {
    expect(
      flattenCompany({ name: 'Simplex', id: 'acc_1', plan: 'pro' })
    ).toEqual({
      company_name: 'Simplex',
      company_id: 'acc_1',
      company_plan: 'pro',
    });
  });

  it('objeto sem nome nao inventa company_name vazio', () => {
    expect(flattenCompany({ id: 'acc_1' })).toEqual({ company_id: 'acc_1' });
  });

  it('ausencia de company nao produz nada', () => {
    expect(flattenCompany(undefined)).toEqual({});
    expect(flattenCompany(null)).toEqual({});
    expect(flattenCompany('Simplex')).toEqual({});
  });
});

describe('buildContactPayload', () => {
  it('leva os campos de topo e os adicionais para os lugares certos', () => {
    const payload = buildContactPayload({
      email: 'ana@exemplo.com.br',
      phone_number: '+5511999998888',
      company: { name: 'Simplex' },
      city: 'Curitiba',
      signed_up_at: '2026-08-19T00:00:00Z',
    });

    expect(payload.email).toBe('ana@exemplo.com.br');
    expect(payload.phone_number).toBe('+5511999998888');
    expect(payload.additional_attributes).toEqual({
      city: 'Curitiba',
      signed_up_at: '2026-08-19T00:00:00Z',
      company_name: 'Simplex',
    });
  });

  it('signed_up_at viaja — antes nem existia na superficie', () => {
    const payload = buildContactPayload({
      signed_up_at: '2026-08-19T00:00:00Z',
    });

    expect(payload.additional_attributes.signed_up_at).toBe(
      '2026-08-19T00:00:00Z'
    );
  });

  it('company como objeto vence company_name legado quando os dois vem', () => {
    const payload = buildContactPayload({
      company_name: 'Antiga',
      company: { name: 'Nova' },
    });

    expect(payload.additional_attributes.company_name).toBe('Nova');
  });

  it('company_name sozinho continua funcionando — o legado nao quebra', () => {
    const payload = buildContactPayload({ company_name: 'Simplex' });

    expect(payload.additional_attributes.company_name).toBe('Simplex');
  });

  describe('a regra de verbo, que o bloco pede explicita', () => {
    it('update MESCLA: campo nao enviado fica FORA do payload, para o servidor nao apagar', () => {
      const payload = buildContactPayload(
        { phone_number: '+5511999998888' },
        { merge: true }
      );

      expect(payload.phone_number).toBe('+5511999998888');
      expect('email' in payload).toBe(false);
      expect('name' in payload).toBe(false);
    });

    it('set SUBSTITUI: campo nao enviado vai no payload como vazio', () => {
      const payload = buildContactPayload(
        { phone_number: '+5511999998888' },
        { merge: false }
      );

      expect(payload.phone_number).toBe('+5511999998888');
      expect('email' in payload).toBe(true);
      expect(payload.email).toBeUndefined();
    });

    it('set e o default, porque e o comportamento historico do setUser', () => {
      expect('email' in buildContactPayload({ name: 'Ana' })).toBe(true);
    });
  });

  it('custom_attributes so entra quando o site manda — objeto vazio e diferente de ausencia', () => {
    expect('custom_attributes' in buildContactPayload({ name: 'Ana' })).toBe(
      false
    );
    expect(
      buildContactPayload({ name: 'Ana', custom_attributes: {} })
        .custom_attributes
    ).toEqual({});
  });
});

// Bloco 5.19 — o repasse do `identity_token`.
//
// Este e o ponto EXATO onde o formato novo morria: a allowlist deste modulo descartava a
// credencial em silencio, entao o servidor — que ja sabia validar o JWT desde a primeira entrega
// do bloco — nunca recebia um. Nao havia erro, nao havia log, nao havia teste vermelho: so um
// campo que sumia entre o site e a API.
describe('buildContactPayload — a credencial do 5.19', () => {
  it('repassa o identity_token que o SDK anexou', () => {
    expect(
      buildContactPayload({ name: 'Ana', identity_token: 'jwt.de.verdade' })
        .identity_token
    ).toBe('jwt.de.verdade');
  });

  it('repassa tambem no verbo que MESCLA, porque credencial nao e campo de contato', () => {
    expect(
      buildContactPayload(
        { phone_number: '+5511999998888', identity_token: 'jwt.de.verdade' },
        { merge: true }
      ).identity_token
    ).toBe('jwt.de.verdade');
  });

  // A CONDICAO RUIM FORCADA. Sem este exemplo, "repassa o token" passaria tambem numa
  // implementacao que gravasse `identity_token: undefined` em toda chamada — e ai o corpo da
  // requisicao carregaria uma chave de credencial vazia em todo `setUser` de todo visitante
  // anonimo de todo site.
  it('sem token, a chave NAO aparece no corpo — ausencia e diferente de vazio', () => {
    expect('identity_token' in buildContactPayload({ name: 'Ana' })).toBe(
      false
    );
    expect(
      'identity_token' in
        buildContactPayload({ name: 'Ana', identity_token: '' })
    ).toBe(false);
  });

  it('conviver com o identifier_hash e o caso comum, nao o conflito', () => {
    const payload = buildContactPayload({
      name: 'Ana',
      identifier_hash: 'hmac-legado',
      identity_token: 'jwt.de.verdade',
    });

    expect(payload.identifier_hash).toBe('hmac-legado');
    expect(payload.identity_token).toBe('jwt.de.verdade');
  });
});
