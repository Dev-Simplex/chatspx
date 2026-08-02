/* global axios */
import TeamsAPI from 'dashboard/api/teams';

/**
 * Chamadas de membro de time usadas pela visão do supervisor.
 *
 * O POST reaproveita o client de `api/teams.js`. O DELETE mora aqui porque
 * aquele client só tem `getAgents/addAgents/updateAgents` — e esta frente não
 * pode tocar em `api/teams.js` (outros agentes trabalham na mesma árvore). Se a
 * remoção passar a ser usada por outra tela, promova para `TeamsAPI#removeAgents`.
 *
 * Ambas devolvem a promise crua do axios de propósito: o erro original chega
 * inteiro na tela (o `teamMembers` da store embrulha em `new Error(error)` e
 * perde o `response.status`, que é justamente como distinguimos o 403 de "time
 * não supervisionado / agente fora do pool" de uma falha qualquer).
 */
export const addTeamMembers = ({ teamId, userIds }) =>
  TeamsAPI.addAgents({ teamId, agentsList: userIds });

export const removeTeamMembers = ({ teamId, userIds }) =>
  axios.delete(`${TeamsAPI.url}/${teamId}/team_members`, {
    data: { user_ids: userIds },
  });
