import {
  MODOS,
  MODOS_POSSE,
  politicaPadrao,
  normalizarCap,
  normalizarPool,
  moverNoPool,
  politicaParaForm,
  validarPolitica,
  montarPayload,
} from '../RodizioPoliticaPage.vue';

const membros = [
  { id: 11, name: 'Ana', email: 'ana@spx.app' },
  { id: 22, name: 'Bruno', email: 'bruno@spx.app' },
  { id: 33, name: 'Célia', email: 'celia@spx.app' },
];

const formValido = extra => ({ ...politicaPadrao(), ...extra });

describe('normalizarCap', () => {
  it('trata vazio como sem teto', () => {
    expect(normalizarCap('')).toBeNull();
    expect(normalizarCap(null)).toBeNull();
    expect(normalizarCap(undefined)).toBeNull();
  });

  it('aceita número em string (é o que o input devolve)', () => {
    expect(normalizarCap('4')).toBe(4);
    expect(normalizarCap(4)).toBe(4);
  });

  it('não confunde zero com vazio', () => {
    expect(normalizarCap(0)).toBe(0);
    expect(normalizarCap('0')).toBe(0);
  });

  it('descarta lixo', () => {
    expect(normalizarCap('abc')).toBeNull();
  });
});

describe('normalizarPool', () => {
  it('preserva a ordem salva — ela É a ordem do rodízio', () => {
    const pool = [
      { user_id: 33, ativo: true, cap: 2 },
      { user_id: 11, ativo: true, cap: null },
    ];
    const linhas = normalizarPool(membros, pool);
    expect(linhas.map(l => l.user_id)).toEqual([33, 11, 22]);
  });

  it('entrar no time NÃO entra no rodízio: membro novo vai pro fim, desligado', () => {
    const linhas = normalizarPool(membros, [{ user_id: 11, ativo: true }]);
    const bruno = linhas.find(l => l.user_id === 22);
    expect(bruno).toMatchObject({ ativo: false, cap: null });
    expect(linhas[linhas.length - 1].user_id).toBe(33);
  });

  it('quem saiu do time some do pool', () => {
    const pool = [
      { user_id: 99, ativo: true, cap: 5 },
      { user_id: 11, ativo: true },
    ];
    const linhas = normalizarPool(membros, pool);
    expect(linhas.map(l => l.user_id)).not.toContain(99);
    expect(linhas[0].user_id).toBe(11);
  });

  it('user_id vem como número mesmo se o backend mandar string', () => {
    const linhas = normalizarPool(membros, [{ user_id: '22', ativo: true }]);
    expect(linhas[0].user_id).toBe(22);
  });

  it('ignora entrada repetida', () => {
    const pool = [
      { user_id: 11, ativo: true },
      { user_id: 11, ativo: false },
    ];
    const linhas = normalizarPool(membros, pool);
    expect(linhas.filter(l => l.user_id === 11)).toHaveLength(1);
  });

  it('usa o nome ATUAL do membro, não o congelado na política', () => {
    const linhas = normalizarPool(membros, [
      { user_id: 11, ativo: true, name: 'Nome antigo' },
    ]);
    expect(linhas[0].name).toBe('Ana');
  });

  it('sem pool salvo, lista o time inteiro desligado', () => {
    const linhas = normalizarPool(membros, []);
    expect(linhas).toHaveLength(3);
    expect(linhas.every(l => l.ativo === false)).toBe(true);
  });

  it('aguenta argumentos ausentes', () => {
    expect(normalizarPool()).toEqual([]);
    expect(normalizarPool(membros, null)).toHaveLength(3);
  });
});

describe('moverNoPool', () => {
  const pool = [{ user_id: 1 }, { user_id: 2 }, { user_id: 3 }];

  it('sobe e desce trocando os vizinhos', () => {
    expect(moverNoPool(pool, 2, -1).map(l => l.user_id)).toEqual([1, 3, 2]);
    expect(moverNoPool(pool, 0, 1).map(l => l.user_id)).toEqual([2, 1, 3]);
  });

  it('nas pontas devolve a mesma lista em vez de embaralhar', () => {
    expect(moverNoPool(pool, 0, -1)).toBe(pool);
    expect(moverNoPool(pool, 2, 1)).toBe(pool);
    expect(moverNoPool(pool, 9, -1)).toBe(pool);
  });

  it('não muta a lista original', () => {
    moverNoPool(pool, 1, -1);
    expect(pool.map(l => l.user_id)).toEqual([1, 2, 3]);
  });
});

describe('politicaParaForm', () => {
  it('sem política, devolve o padrão com o time inteiro desligado', () => {
    const form = politicaParaForm(null, membros);
    expect(form.ativo).toBe(false);
    expect(form.pool).toHaveLength(3);
    expect(form.pool.every(l => l.ativo === false)).toBe(true);
  });

  it('carrega a política existente e casa o pool com o time', () => {
    const form = politicaParaForm(
      {
        ativo: true,
        modo: 'fila',
        modo_posse: 'assignee',
        continuidade_ativa: true,
        continuidade_dias: 45,
        sla_assumir_minutos: 7,
        repasse_automatico: true,
        max_repasses: 2,
        pool_esgotado_destino_user_id: 33,
        gatilho_sem_ia: true,
        pool: [{ user_id: 22, ativo: true, cap: 3 }],
      },
      membros
    );
    expect(form).toMatchObject({
      ativo: true,
      modo: 'fila',
      modo_posse: 'assignee',
      continuidade_dias: 45,
      sla_assumir_minutos: 7,
      max_repasses: 2,
      pool_esgotado_destino_user_id: 33,
      gatilho_sem_ia: true,
    });
    expect(form.pool[0]).toMatchObject({ user_id: 22, ativo: true, cap: 3 });
  });

  it('modo desconhecido cai no padrão em vez de sujar o select', () => {
    const form = politicaParaForm({ modo: 'zebra', modo_posse: 'x' }, membros);
    expect(MODOS).toContain(form.modo);
    expect(MODOS_POSSE).toContain(form.modo_posse);
  });
});

describe('validarPolitica', () => {
  it('aceita o padrão desligado', () => {
    expect(validarPolitica(politicaPadrao())).toEqual([]);
  });

  it('recusa SLA zero, negativo ou quebrado', () => {
    expect(validarPolitica(formValido({ sla_assumir_minutos: 0 }))).toContain(
      'SLA'
    );
    expect(validarPolitica(formValido({ sla_assumir_minutos: -1 }))).toContain(
      'SLA'
    );
    expect(validarPolitica(formValido({ sla_assumir_minutos: '' }))).toContain(
      'SLA'
    );
    expect(validarPolitica(formValido({ sla_assumir_minutos: 1.5 }))).toContain(
      'SLA'
    );
  });

  it('max_repasses aceita 0 (sem teto) mas recusa negativo', () => {
    expect(validarPolitica(formValido({ max_repasses: 0 }))).not.toContain(
      'MAX_REPASSES'
    );
    expect(validarPolitica(formValido({ max_repasses: -1 }))).toContain(
      'MAX_REPASSES'
    );
  });

  it('só cobra dias quando a continuidade está ligada', () => {
    // `continuidade_ativa: false` vai EXPLICITO: antes este caso dependia de o padrao da tela vir
    // desligado, e o padrao passou a espelhar a coluna (default true). Teste que se apoia em valor
    // padrao passa a testar o padrao, nao a regra.
    expect(
      validarPolitica(
        formValido({ continuidade_ativa: false, continuidade_dias: 0 })
      )
    ).not.toContain('CONTINUIDADE_DIAS');
    expect(
      validarPolitica(
        formValido({ continuidade_ativa: true, continuidade_dias: 0 })
      )
    ).toContain('CONTINUIDADE_DIAS');
  });

  it('cap vazio passa, cap zero não', () => {
    const comCap = cap =>
      formValido({
        ativo: true,
        pool: [{ user_id: 11, ativo: true, cap }],
      });
    expect(validarPolitica(comCap(''))).not.toContain('CAP');
    expect(validarPolitica(comCap(3))).not.toContain('CAP');
    expect(validarPolitica(comCap(0))).toContain('CAP');
    expect(validarPolitica(comCap(-2))).toContain('CAP');
  });

  it('ignora cap de quem está fora do rodízio', () => {
    const form = formValido({
      ativo: true,
      pool: [
        { user_id: 11, ativo: true, cap: 2 },
        { user_id: 22, ativo: false, cap: 0 },
      ],
    });
    expect(validarPolitica(form)).not.toContain('CAP');
  });

  it('barra política ligada com o pool vazio — não distribuiria nada', () => {
    const form = formValido({
      ativo: true,
      pool: [{ user_id: 11, ativo: false, cap: null }],
    });
    expect(validarPolitica(form)).toContain('POOL_VAZIO');
  });

  it('política desligada pode ficar com o pool vazio', () => {
    const form = formValido({
      ativo: false,
      pool: [{ user_id: 11, ativo: false, cap: null }],
    });
    expect(validarPolitica(form)).not.toContain('POOL_VAZIO');
  });

  it('recusa modo fora do contrato', () => {
    expect(validarPolitica(formValido({ modo: 'zebra' }))).toContain('MODO');
    expect(validarPolitica(formValido({ modo_posse: 'zebra' }))).toContain(
      'MODO_POSSE'
    );
  });
});

describe('montarPayload', () => {
  const form = politicaParaForm(
    {
      ativo: true,
      modo: 'rodizio',
      modo_posse: 'designacao',
      continuidade_ativa: true,
      continuidade_dias: '15',
      sla_assumir_minutos: '8',
      repasse_automatico: true,
      max_repasses: '0',
      pool_esgotado_destino_user_id: '33',
      gatilho_sem_ia: false,
      pool: [
        { user_id: 22, ativo: true, cap: '3' },
        { user_id: 11, ativo: false, cap: '' },
      ],
    },
    membros
  );

  it('manda exatamente as chaves do contrato', () => {
    expect(Object.keys(montarPayload(form)).sort()).toEqual(
      [
        'ativo',
        'continuidade_ativa',
        'continuidade_dias',
        'gatilho_sem_ia',
        'max_repasses',
        'modo',
        'modo_posse',
        'pool',
        'pool_esgotado_destino_user_id',
        'repasse_automatico',
        'sla_assumir_minutos',
      ].sort()
    );
  });

  it('converte os numéricos que o input devolve como string', () => {
    const payload = montarPayload(form);
    expect(payload.continuidade_dias).toBe(15);
    expect(payload.sla_assumir_minutos).toBe(8);
    expect(payload.max_repasses).toBe(0);
    expect(payload.pool_esgotado_destino_user_id).toBe(33);
  });

  it('preserva a ordem do pool e manda também quem está desligado', () => {
    const payload = montarPayload(form);
    expect(payload.pool.map(l => l.user_id)).toEqual([22, 11, 33]);
    expect(payload.pool[1]).toEqual({ user_id: 11, ativo: false, cap: null });
  });

  it('não vaza name/email para o backend', () => {
    const payload = montarPayload(form);
    payload.pool.forEach(linha => {
      expect(Object.keys(linha).sort()).toEqual(['ativo', 'cap', 'user_id']);
    });
  });

  it('destino vazio vira null, não zero', () => {
    const payload = montarPayload(
      formValido({ pool_esgotado_destino_user_id: '' })
    );
    expect(payload.pool_esgotado_destino_user_id).toBeNull();
  });
});
