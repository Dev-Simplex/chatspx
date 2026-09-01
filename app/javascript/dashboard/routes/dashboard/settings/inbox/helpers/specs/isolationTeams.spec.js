import {
  ISOLATION_RULES,
  ISOLATION_TEAM_IDS_KEYS,
  appliesToAllTeams,
  buildIsolationTeamIdsPayload,
  normalizeTeamIds,
  teamIdsToOptions,
} from '../isolationTeams';

const TIMES = [
  { id: 3, name: 'Comercial' },
  { id: 5, name: 'Suporte' },
];

describe('ISOLATION_RULES', () => {
  it('deriva o nome da chave do nome da flag', () => {
    expect(ISOLATION_TEAM_IDS_KEYS).toEqual([
      'team_message_isolation_team_ids',
      'agent_message_isolation_team_ids',
      'agent_conversation_isolation_team_ids',
    ]);
    ISOLATION_RULES.forEach(({ flag, teamIdsKey }) => {
      expect(teamIdsKey).toBe(`${flag}_team_ids`);
    });
  });
});

describe('normalizeTeamIds', () => {
  it('aceita o que o MultiSelect devolve (objetos) e o que a API devolve (ids)', () => {
    expect(normalizeTeamIds([{ id: 3, name: 'Comercial' }, { id: 5 }])).toEqual(
      [3, 5]
    );
    expect(normalizeTeamIds([3, 5])).toEqual([3, 5]);
  });

  it('converte id em string, que é o que volta de query string e de <select>', () => {
    expect(normalizeTeamIds(['3', { id: '5' }])).toEqual([3, 5]);
  });

  it('preserva a ordem de escolha e não repete time', () => {
    expect(normalizeTeamIds([5, 3, 5, { id: 3 }])).toEqual([5, 3]);
  });

  it('descarta lixo em vez de mandar id inválido pro backend', () => {
    expect(normalizeTeamIds([null, undefined, 'abc', 0, -1, {}])).toEqual([]);
  });

  it('não quebra com valor ausente — sem lista é lista vazia', () => {
    expect(normalizeTeamIds(undefined)).toEqual([]);
    expect(normalizeTeamIds(null)).toEqual([]);
    expect(normalizeTeamIds('3')).toEqual([]);
  });
});

describe('appliesToAllTeams', () => {
  it('VAZIO = vale para TODOS os times (é o comportamento de hoje)', () => {
    expect(appliesToAllTeams([])).toBe(true);
    expect(appliesToAllTeams(undefined)).toBe(true);
    // lista só com lixo continua sendo "todos", não "nenhum"
    expect(appliesToAllTeams(['abc'])).toBe(true);
  });

  it('com time escolhido a regra passa a ser restrita', () => {
    expect(appliesToAllTeams([3])).toBe(false);
    expect(appliesToAllTeams([{ id: 3 }])).toBe(false);
  });
});

describe('teamIdsToOptions', () => {
  it('traduz id em opção do MultiSelect', () => {
    expect(teamIdsToOptions([5, 3], TIMES)).toEqual([
      { id: 5, name: 'Suporte' },
      { id: 3, name: 'Comercial' },
    ]);
  });

  it('time que sumiu (ou store ainda carregando) NÃO some da seleção', () => {
    expect(teamIdsToOptions([9], TIMES)).toEqual([{ id: 9, name: '#9' }]);
    expect(teamIdsToOptions([3], [])).toEqual([{ id: 3, name: '#3' }]);
  });
});

describe('buildIsolationTeamIdsPayload', () => {
  const selecaoVazia = {
    team_message_isolation_team_ids: [],
    agent_message_isolation_team_ids: [],
    agent_conversation_isolation_team_ids: [],
  };

  it('inbox SEM os campos e nada escolhido: as chaves NÃO vão no payload', () => {
    // Este é o guard do "salvar apagava as conditions": mandar [] de um campo que a tela nunca
    // recebeu apagaria o escopo de quem já tinha configurado.
    const payload = buildIsolationTeamIdsPayload({ id: 1 }, selecaoVazia);
    expect(payload).toEqual({});
    ISOLATION_TEAM_IDS_KEYS.forEach(key => {
      expect(key in payload).toBe(false);
    });
  });

  it('inbox SEM o campo mas admin escolheu time: manda (é escolha nova)', () => {
    const payload = buildIsolationTeamIdsPayload(
      { id: 1 },
      { ...selecaoVazia, team_message_isolation_team_ids: [{ id: 3 }] }
    );
    expect(payload).toEqual({ team_message_isolation_team_ids: [3] });
  });

  it('inbox COM o campo e tela intocada: reenvia o mesmo valor (idempotente)', () => {
    const inbox = {
      team_message_isolation_team_ids: [3, 5],
      agent_message_isolation_team_ids: [],
      agent_conversation_isolation_team_ids: [],
    };
    const payload = buildIsolationTeamIdsPayload(inbox, {
      ...selecaoVazia,
      team_message_isolation_team_ids: [3, 5],
    });
    expect(payload).toEqual({
      team_message_isolation_team_ids: [3, 5],
      agent_message_isolation_team_ids: [],
      agent_conversation_isolation_team_ids: [],
    });
  });

  it('admin limpou a lista de um campo que existia: manda [] = volta a valer para todos', () => {
    const payload = buildIsolationTeamIdsPayload(
      { team_message_isolation_team_ids: [3, 5] },
      selecaoVazia
    );
    expect(payload).toEqual({ team_message_isolation_team_ids: [] });
  });

  it('normaliza o que veio do MultiSelect em cada uma das três regras', () => {
    const inbox = {
      team_message_isolation_team_ids: [],
      agent_message_isolation_team_ids: [],
      agent_conversation_isolation_team_ids: [],
    };
    const payload = buildIsolationTeamIdsPayload(inbox, {
      team_message_isolation_team_ids: [{ id: 3, name: 'Comercial' }],
      agent_message_isolation_team_ids: ['5', 5],
      agent_conversation_isolation_team_ids: [{ id: 3 }, { id: 5 }],
    });
    expect(payload).toEqual({
      team_message_isolation_team_ids: [3],
      agent_message_isolation_team_ids: [5],
      agent_conversation_isolation_team_ids: [3, 5],
    });
  });

  it('não inventa outras chaves no payload da inbox', () => {
    const payload = buildIsolationTeamIdsPayload(
      { team_message_isolation_team_ids: [3], name: 'Caixa' },
      selecaoVazia
    );
    expect(Object.keys(payload)).toEqual(['team_message_isolation_team_ids']);
  });

  it('aguenta ser chamado sem argumento nenhum', () => {
    expect(buildIsolationTeamIdsPayload()).toEqual({});
  });
});
