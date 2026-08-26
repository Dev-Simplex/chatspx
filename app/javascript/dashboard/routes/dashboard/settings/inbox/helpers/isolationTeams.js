/**
 * Escopo por time das 3 regras de isolamento da caixa de entrada.
 *
 * As regras continuam sendo booleanos por INBOX; o que estes helpers modelam é a lista de times em
 * que cada uma vale. O critério é o TIME DA CONVERSA (`conversations.team_id`) nas três — é o modelo
 * que o `team_message_isolation` já usa, não gera ambiguidade para quem pertence a dois times e
 * responde "quem vê esta conversa?" olhando só a conversa.
 *
 * Duas decisões moram aqui e valem para o front inteiro:
 *
 * 1. LISTA VAZIA = TODOS OS TIMES. É o comportamento de hoje, então nenhuma inbox já configurada
 *    muda de comportamento no deploy. A regra só vira restrita quando o admin escolhe times.
 * 2. Conversa SEM time (`team_id IS NULL`) não é isolada nas DUAS regras de MENSAGEM. Ela nasce sem
 *    time, antes da triagem; isolar aí esconderia lead novo de quem precisa atender.
 *    `agent_conversation_isolation` é a EXCEÇÃO e continua isolando a conversa sem time: ali o que
 *    fecha a conversa é "tem outro dono", critério que não é o time — isentá-la abriria no deploy a
 *    conversa do colega ainda sem triagem. No backend isso é `Inbox::TEAMLESS_EXEMPT_RULES`; aqui o
 *    front só avisa, e o aviso é DIFERENTE por regra (ver `isolationNoTeamStillIsolatedHint`).
 */

// Os nomes das chaves derivam do nome da flag: quem lê o payload não precisa de tabela de-para.
export const ISOLATION_RULES = [
  {
    flag: 'team_message_isolation',
    teamIdsKey: 'team_message_isolation_team_ids',
  },
  {
    flag: 'agent_message_isolation',
    teamIdsKey: 'agent_message_isolation_team_ids',
  },
  {
    flag: 'agent_conversation_isolation',
    teamIdsKey: 'agent_conversation_isolation_team_ids',
  },
];

export const ISOLATION_TEAM_IDS_KEYS = ISOLATION_RULES.map(
  rule => rule.teamIdsKey
);

/**
 * Aceita o que o MultiSelect devolve (objetos `{ id, name }`) e o que a API devolve (ids crus,
 * às vezes em string), e sempre entrega ids numéricos, únicos e na ordem de escolha.
 */
export const normalizeTeamIds = value => {
  if (!Array.isArray(value)) return [];

  const ids = value
    .map(item => (item && typeof item === 'object' ? item.id : item))
    .map(id => Number(id))
    .filter(id => Number.isInteger(id) && id > 0);

  return [...new Set(ids)];
};

/** Vazio = a regra vale para todos os times. Não é "nenhum time". */
export const appliesToAllTeams = value => normalizeTeamIds(value).length === 0;

/**
 * Ids -> opções do MultiSelect. Time que sumiu (ou que ainda não carregou do store) não pode
 * evaporar da seleção só porque não achamos o nome: ele volta como `#id` e continua selecionado.
 */
export const teamIdsToOptions = (value, teams = []) =>
  normalizeTeamIds(value).map(id => {
    const team = teams.find(item => Number(item?.id) === id);
    return { id, name: team?.name || `#${id}` };
  });

/**
 * Monta a parte do PATCH que carrega as listas de times.
 *
 * A regra que importa é a de baixo: quando a inbox NÃO trouxe o campo (backend ainda sem a coluna,
 * serializer omitindo, front deployado antes) e o admin não escolheu nada, a chave não vai no
 * payload. Mandar `[]` de um campo que nunca conhecemos apagaria a configuração de quem já tinha —
 * é o mesmo estrago do "salvar apagava as conditions" do canvas.
 */
export const buildIsolationTeamIdsPayload = (inbox = {}, selection = {}) =>
  ISOLATION_RULES.reduce((payload, { teamIdsKey }) => {
    const stored = inbox?.[teamIdsKey];
    const current = normalizeTeamIds(selection?.[teamIdsKey]);

    // A inbox trouxe o campo: mandamos o valor da tela (inclusive vazio — aí o admin limpou de
    // propósito e quer a regra valendo para todos de novo).
    if (Array.isArray(stored)) {
      payload[teamIdsKey] = current;
      return payload;
    }

    // Campo desconhecido: só mandamos se o admin escolheu algum time nesta tela.
    if (current.length) payload[teamIdsKey] = current;

    return payload;
  }, {});
