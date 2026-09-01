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
      expect('clear_attributes' in payload).toBe(false);
    });

    it('set SUBSTITUI: campo nao enviado entra na lista de apagamento', () => {
      const payload = buildContactPayload(
        { phone_number: '+5511999998888' },
        { merge: false }
      );

      expect(payload.phone_number).toBe('+5511999998888');
      expect(payload.clear_attributes).toEqual(['email', 'name', 'avatar_url']);
    });

    /**
     * A ASSERCAO QUE FALTAVA, e a razao de ela existir.
     *
     * O spec anterior media `'email' in payload === true` e `payload.email === undefined`. Passava
     * verde e nao media nada: o payload nao viaja como objeto, viaja como JSON, e `JSON.stringify`
     * descarta chave com `undefined`. Medido no vermelho deste bloco, os dois verbos produziam
     * `{"phone_number":"+5511999998888"}` — identicos byte a byte. "Substitui" era um comentario.
     *
     * Por isso a medicao e feita DEPOIS de serializar: e a unica forma da assercao falhar quando o
     * defeito voltar.
     */
    it('set e update NAO produzem o mesmo payload na REDE — medido depois do JSON', () => {
      const usuario = { phone_number: '+5511999998888' };
      const comSet = JSON.stringify(
        buildContactPayload(usuario, { merge: false })
      );
      const comUpdate = JSON.stringify(
        buildContactPayload(usuario, { merge: true })
      );

      expect(comSet).not.toBe(comUpdate);
      expect(JSON.parse(comSet).clear_attributes).toContain('email');
      expect(JSON.parse(comUpdate)).not.toHaveProperty('clear_attributes');
    });

    it('set com TODOS os campos nao pede apagamento nenhum', () => {
      const payload = buildContactPayload(
        {
          email: 'ana@exemplo.com.br',
          name: 'Ana',
          avatar_url: 'https://exemplo.com.br/a.png',
          phone_number: '+5511999998888',
        },
        { merge: false }
      );

      expect('clear_attributes' in payload).toBe(false);
    });

    it('set e o default, porque e o comportamento historico do setUser', () => {
      expect(buildContactPayload({ name: 'Ana' }).clear_attributes).toContain(
        'email'
      );
    });

    it('a lista de apagamento nao inclui campo que o site MANDOU vazio de proposito', () => {
      // String vazia e uma DECLARACAO ("nao tem e-mail"), nao uma omissao. Ela viaja como valor e
      // o servidor a trata pelo caminho normal; nao e o mesmo fato que "o site nem mencionou".
      const payload = buildContactPayload(
        { name: 'Ana', email: '' },
        { merge: false }
      );

      expect(payload.email).toBe('');
      expect(payload.clear_attributes).not.toContain('email');
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
